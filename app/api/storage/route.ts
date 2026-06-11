import { NextRequest, NextResponse } from 'next/server';
import { promises as fs } from 'fs';
import path from 'path';

// File-based storage rooted at <project>/storage. Each collection is a flat set
// of JSON files; we never allow path traversal outside this directory.
const STORAGE_DIR = path.join(process.cwd(), 'storage');

const PREFIXES = ['group', 'env'] as const;
const SINGLETONS = ['history'] as const;

async function ensureDir() {
  await fs.mkdir(STORAGE_DIR, { recursive: true });
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

// GET /api/storage            -> { environments, groups, history }
// GET /api/storage?name=env-1 -> single document
export async function GET(req: NextRequest) {
  await ensureDir();
  const name = req.nextUrl.searchParams.get('name');

  if (name) {
    const file = resolveFile(name);
    if (!file) return NextResponse.json({ error: 'invalid name' }, { status: 400 });
    try {
      const raw = await fs.readFile(file, 'utf8');
      return NextResponse.json(JSON.parse(raw));
    } catch {
      return NextResponse.json(null);
    }
  }

  const files = await fs.readdir(STORAGE_DIR).catch(() => [] as string[]);
  const environments: unknown[] = [];
  const groups: unknown[] = [];
  let history: unknown[] = [];

  await Promise.all(
    files
      .filter((f) => f.endsWith('.json'))
      .map(async (f) => {
        try {
          const data = JSON.parse(await fs.readFile(path.join(STORAGE_DIR, f), 'utf8'));
          if (f.startsWith('env-')) environments.push(data);
          else if (f.startsWith('group-')) groups.push(data);
          else if (f === 'history.json') history = Array.isArray(data) ? data : [];
        } catch {
          /* skip unreadable file */
        }
      })
  );

  return NextResponse.json({ environments, groups, history });
}

// PUT /api/storage  body: { name, data }
export async function PUT(req: NextRequest) {
  await ensureDir();
  const { name, data } = await req.json().catch(() => ({}));
  const file = typeof name === 'string' ? resolveFile(name) : null;
  if (!file) return NextResponse.json({ error: 'invalid name' }, { status: 400 });
  await fs.writeFile(file, JSON.stringify(data, null, 2), 'utf8');
  return NextResponse.json({ ok: true });
}

// DELETE /api/storage?name=group-1
export async function DELETE(req: NextRequest) {
  await ensureDir();
  const name = req.nextUrl.searchParams.get('name');
  const file = name ? resolveFile(name) : null;
  if (!file) return NextResponse.json({ error: 'invalid name' }, { status: 400 });
  await fs.rm(file, { force: true });
  return NextResponse.json({ ok: true });
}
