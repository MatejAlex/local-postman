import { NextRequest, NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import os from 'os';
import path from 'path';

// Runtime data lives outside the repo, because it holds whatever credentials were
// sent; keeping it here would put them in every zip, backup and `git clean -xdf`.
const STORAGE_DIR = process.env.LOCAL_POSTMAN_DIR || path.join(os.homedir(), '.local-postman');

// The repo's storage/ is seed-only: copied into STORAGE_DIR on a first run.
const SEED_DIR = path.join(process.cwd(), 'storage');

// 'env' was dropped in v1.7 along with environments; an env-*.json left in the
// storage dir is simply never read again.
const PREFIXES = ['group'] as const;
const SINGLETONS = ['history'] as const;

// Passwords are held here instead of in the collection, so a group-*.json can be handed to
// someone else as it sits. `resolveFile` rejects the name, so it is never served to the client.
const SECRETS_FILE = path.join(STORAGE_DIR, 'secrets.json');

async function ensureDir() {
  await fs.mkdir(STORAGE_DIR, { recursive: true });
  const existing = await fs.readdir(STORAGE_DIR);
  if (existing.some((file) => file.endsWith('.json'))) {
    return;
  }
  const seeds = await fs.readdir(SEED_DIR).catch(() => [] as string[]);
  for (const file of seeds) {
    if (file.endsWith('.json')) {
      await fs.copyFile(path.join(SEED_DIR, file), path.join(STORAGE_DIR, file));
    }
  }
}

/** Validate a logical name and map it to a safe absolute file path. */
function resolveFile(name: string): string | null {
  if (!/^[a-z0-9_-]+$/i.test(name)) return null;
  if ((SINGLETONS as readonly string[]).includes(name)) {
    return path.join(STORAGE_DIR, `${name}.json`);
  }
  const prefix = name.split('-')[0];
  if (!(PREFIXES as readonly string[]).includes(prefix)) return null;
  const file = path.join(STORAGE_DIR, `${name}.json`);
  // Defense in depth: the resolved path must stay inside STORAGE_DIR.
  if (path.dirname(file) !== STORAGE_DIR) return null;
  return file;
}

/* -------------------------------------------------------------------------- */
/* Passwords                                                                   */
/* -------------------------------------------------------------------------- */

/** Owner id -> password. The id is a collection's, or `collectionId/requestId`. */
type Secrets = Record<string, string>;

/** Only the shape a password sits in; a stored file may be anything at all. */
interface BasicShape {
  password?: string;
}

interface PasswordSlot {
  key: string;
  basic: BasicShape;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** The `basic` object of an auth block, if this value has one. */
function basicOf(owner: unknown): BasicShape | null {
  if (!isRecord(owner) || !isRecord(owner.auth) || !isRecord(owner.auth.basic)) return null;
  return owner.auth.basic as BasicShape;
}

/**
 * Every place a password can sit in a collection, paired with the key that owns it: the
 * collection's own auth first, then one per request. `groupName` is the file name, which
 * storage.ts keeps identical to the collection's id.
 */
function passwordSlots(data: unknown, groupName: string): PasswordSlot[] {
  const slots: PasswordSlot[] = [];
  if (!isRecord(data)) return slots;

  const own = basicOf(data);
  if (own) slots.push({ key: groupName, basic: own });

  const requests = Array.isArray(data.requests) ? data.requests : [];
  for (const req of requests) {
    const basic = basicOf(req);
    if (basic && isRecord(req) && typeof req.id === 'string') {
      slots.push({ key: `${groupName}/${req.id}`, basic });
    }
  }
  return slots;
}

async function readSecrets(): Promise<Secrets> {
  try {
    const parsed: unknown = JSON.parse(await fs.readFile(SECRETS_FILE, 'utf8'));
    return isRecord(parsed) ? (parsed as Secrets) : {};
  } catch {
    // Missing or unparseable reads as empty: a collection then arrives with a blank password
    // box rather than failing the whole load.
    return {};
  }
}

async function writeSecrets(secrets: Secrets): Promise<void> {
  await fs.writeFile(SECRETS_FILE, JSON.stringify(secrets, null, 2), 'utf8');
}

/** Move the incoming passwords into the secrets map and blank them on the group. */
function extractPasswords(data: unknown, groupName: string, secrets: Secrets): boolean {
  let changed = false;
  for (const slot of passwordSlots(data, groupName)) {
    const password = slot.basic.password ?? '';
    if (password === '') {
      // Clearing the box removes the secret rather than storing a blank one.
      if (slot.key in secrets) {
        delete secrets[slot.key];
        changed = true;
      }
      continue;
    }
    if (secrets[slot.key] !== password) {
      secrets[slot.key] = password;
      changed = true;
    }
    slot.basic.password = '';
  }
  return changed;
}

/** Put the stored passwords back on a group heading for the client. */
function applyPasswords(data: unknown, groupName: string, secrets: Secrets): void {
  for (const slot of passwordSlots(data, groupName)) {
    const stored = secrets[slot.key];
    if (stored !== undefined) slot.basic.password = stored;
  }
}

/**
 * Read a stored collection and hand back a client-ready copy.
 *
 * A password still written inline, from before this split existed, is moved into the secrets
 * map and blanked in the file on the spot, so opening the app once cleans every collection and
 * there is no migration to remember. An existing secret always wins, which makes the lift
 * idempotent.
 */
async function hydrateGroup(
  file: string,
  data: unknown,
  groupName: string,
  secrets: Secrets
): Promise<boolean> {
  let lifted = false;
  for (const slot of passwordSlots(data, groupName)) {
    const inline = slot.basic.password ?? '';
    if (inline !== '' && secrets[slot.key] === undefined) {
      secrets[slot.key] = inline;
      lifted = true;
    }
  }

  if (lifted) {
    for (const slot of passwordSlots(data, groupName)) {
      slot.basic.password = '';
    }
    await fs.writeFile(file, JSON.stringify(data, null, 2), 'utf8');
  }

  applyPasswords(data, groupName, secrets);
  return lifted;
}

function isGroup(name: string): boolean {
  return name.startsWith('group-');
}

/* -------------------------------------------------------------------------- */
/* Routes                                                                      */
/* -------------------------------------------------------------------------- */

// GET /api/storage               -> { groups, history }
// GET /api/storage?name=group-1  -> single document
export async function GET(req: NextRequest) {
  await ensureDir();
  const name = req.nextUrl.searchParams.get('name');

  if (name) {
    const file = resolveFile(name);
    if (!file) return NextResponse.json({ error: 'invalid name' }, { status: 400 });
    try {
      const raw = await fs.readFile(file, 'utf8');
      const data: unknown = JSON.parse(raw);
      if (isGroup(name)) {
        const secrets = await readSecrets();
        if (await hydrateGroup(file, data, name, secrets)) {
          await writeSecrets(secrets);
        }
      }
      return NextResponse.json(data);
    } catch {
      return NextResponse.json(null);
    }
  }

  const files = await fs.readdir(STORAGE_DIR).catch(() => [] as string[]);
  const secrets = await readSecrets();
  const groups: unknown[] = [];
  let history: unknown[] = [];
  let lifted = false;

  await Promise.all(
    files
      .filter((f) => f.endsWith('.json'))
      .map(async (f) => {
        try {
          const file = path.join(STORAGE_DIR, f);
          const data: unknown = JSON.parse(await fs.readFile(file, 'utf8'));
          if (f.startsWith('group-')) {
            if (await hydrateGroup(file, data, f.slice(0, -'.json'.length), secrets)) {
              lifted = true;
            }
            groups.push(data);
          } else if (f === 'history.json') {
            history = Array.isArray(data) ? data : [];
          }
        } catch {
          /* skip unreadable file */
        }
      })
  );

  if (lifted) await writeSecrets(secrets);

  return NextResponse.json({ groups, history });
}

// PUT /api/storage  body: { name, data }
export async function PUT(req: NextRequest) {
  await ensureDir();
  const { name, data } = await req.json().catch(() => ({}));
  const file = typeof name === 'string' ? resolveFile(name) : null;
  if (!file) return NextResponse.json({ error: 'invalid name' }, { status: 400 });

  if (isGroup(name)) {
    const secrets = await readSecrets();
    if (extractPasswords(data, name, secrets)) {
      await writeSecrets(secrets);
    }
  }

  await fs.writeFile(file, JSON.stringify(data, null, 2), 'utf8');
  return NextResponse.json({ ok: true });
}

// DELETE /api/storage?name=group-1
export async function DELETE(req: NextRequest) {
  await ensureDir();
  const name = req.nextUrl.searchParams.get('name');
  const file = name ? resolveFile(name) : null;
  if (!file || !name) return NextResponse.json({ error: 'invalid name' }, { status: 400 });

  if (isGroup(name)) {
    const secrets = await readSecrets();
    const owned = Object.keys(secrets).filter((key) => key === name || key.startsWith(`${name}/`));
    if (owned.length > 0) {
      for (const key of owned) {
        delete secrets[key];
      }
      await writeSecrets(secrets);
    }
  }

  await fs.rm(file, { force: true });
  return NextResponse.json({ ok: true });
}
