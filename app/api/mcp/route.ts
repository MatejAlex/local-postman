import { NextRequest, NextResponse } from 'next/server';
import { MCP_PROTOCOL_VERSION } from '../../../src/lib/mcp';

// Server-side MCP client for Streamable HTTP servers.
//
// Why this exists rather than pointing /api/proxy at the endpoint: one MCP call
// is three HTTP requests. The server will not answer `tools/list` until it has
// seen `initialize` and the `notifications/initialized` that follows it, and it
// identifies the session with a header it minted in the middle of that dance.
// Doing it in the browser would mean making the user carry a session id between
// sends by hand, which is exactly the friction this route removes.
//
// Every send opens a fresh session and closes it again. That is a wasted
// round-trip per call and worth it: an inspector whose results depend on what
// you clicked twenty minutes ago is a worse tool than a slightly chattier one.
//
// The security model is the proxy's, for the same reason - see that route.

const TIMEOUT_MS = 30_000;

/** MCP requires the client to accept both, and servers pick per response. */
const ACCEPT = 'application/json, text/event-stream';

interface McpPayload {
  url: string;
  headers?: Record<string, string>;
  method: string;
  params?: Record<string, unknown>;
}

function errorResult(message: string, started: number, status = 0) {
  return NextResponse.json({
    status,
    statusText: '',
    headers: {},
    body: '',
    contentType: '',
    timeMs: Date.now() - started,
    sizeBytes: 0,
    error: message,
  });
}

/** Only allow calls the browser marks as coming from this app. Mirrors /api/proxy. */
function isSameOrigin(req: NextRequest): boolean {
  const site = req.headers.get('sec-fetch-site');
  if (site) return site === 'same-origin' || site === 'none';

  const origin = req.headers.get('origin');
  if (origin) {
    try {
      return new URL(origin).host === req.headers.get('host');
    } catch {
      return false;
    }
  }
  return true;
}

/**
 * Pull the JSON-RPC payload out of a response that may be either plain JSON or
 * an SSE stream carrying one `message` event.
 *
 * Streamable HTTP lets a server answer a POST either way, and which one you get
 * is not something the caller controls, so both have to be understood.
 */
function parseBody(text: string, contentType: string): unknown {
  if (!contentType.includes('text/event-stream')) {
    return JSON.parse(text);
  }

  // Take the last `data:` payload that parses. A stream may carry comments,
  // pings and more than one event; the response to our request is the one we
  // want and it is the last thing sent before the stream closes.
  let last: unknown;
  for (const line of text.split(/\r?\n/)) {
    if (!line.startsWith('data:')) continue;
    const chunk = line.slice(5).trim();
    if (chunk === '') continue;
    try {
      last = JSON.parse(chunk);
    } catch {
      // Not our payload; keep looking.
    }
  }
  if (last === undefined) {
    throw new Error('The event stream carried no JSON payload.');
  }
  return last;
}

interface Hop {
  status: number;
  statusText: string;
  headers: Headers;
  json: unknown;
  raw: string;
}

async function post(
  url: string,
  headers: Record<string, string>,
  message: Record<string, unknown>,
  signal: AbortSignal
): Promise<Hop> {
  const resp = await fetch(url, {
    method: 'POST',
    headers: { ...headers, 'Content-Type': 'application/json', Accept: ACCEPT },
    body: JSON.stringify(message),
    signal,
    redirect: 'follow',
  });

  const raw = await resp.text();
  const contentType = resp.headers.get('content-type') ?? '';

  let json: unknown;
  if (raw.trim() !== '') {
    try {
      json = parseBody(raw, contentType);
    } catch {
      json = undefined;
    }
  }

  return { status: resp.status, statusText: resp.statusText, headers: resp.headers, json, raw };
}

/** The `error` of a JSON-RPC failure, rendered for a human, or null if it succeeded. */
function rpcError(json: unknown): string | null {
  if (json && typeof json === 'object' && 'error' in json) {
    const err = (json as { error: unknown }).error;
    if (err && typeof err === 'object') {
      const { code, message } = err as { code?: number; message?: string };
      return `MCP error ${code ?? '?'}: ${message ?? JSON.stringify(err)}`;
    }
  }
  return null;
}

export async function POST(req: NextRequest) {
  const started = Date.now();

  if (!isSameOrigin(req)) {
    return NextResponse.json(
      { error: 'Cross-origin requests to the MCP route are not allowed.' },
      { status: 403 }
    );
  }

  let payload: McpPayload;
  try {
    payload = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid request payload' }, { status: 400 });
  }

  const { url, headers = {}, method, params = {} } = payload;

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return errorResult('URL must be an absolute http(s) address.', started);
  }
  if (!/^https?:$/.test(parsed.protocol)) {
    return errorResult('Only http(s) URLs are supported.', started);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  const endpoint = parsed.toString();

  try {
    // 1. initialize
    const init = await post(
      endpoint,
      headers,
      {
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: {
          protocolVersion: MCP_PROTOCOL_VERSION,
          capabilities: {},
          clientInfo: { name: 'local-postman', version: '1.6' },
        },
      },
      controller.signal
    );

    if (init.status >= 400) {
      // A 401 here is the common case and the useful one: the headers are wrong.
      return NextResponse.json({
        status: init.status,
        statusText: init.statusText,
        headers: Object.fromEntries(init.headers.entries()),
        body: init.raw,
        contentType: init.headers.get('content-type') ?? '',
        timeMs: Date.now() - started,
        sizeBytes: new TextEncoder().encode(init.raw).length,
        error: `initialize failed with ${init.status}. Check the headers this server requires.`,
      });
    }

    // A refusal arrives as HTTP 200 carrying a JSON-RPC error, so the reason
    // goes in the banner and the payload still goes in the body - a blank
    // response pane next to "refused" is the least useful thing we could show.
    const initError = rpcError(init.json);
    if (initError) {
      const shown = init.json !== undefined ? JSON.stringify(init.json, null, 2) : init.raw;
      return NextResponse.json({
        status: init.status,
        statusText: init.statusText,
        headers: Object.fromEntries(init.headers.entries()),
        body: shown,
        contentType: 'application/json',
        timeMs: Date.now() - started,
        sizeBytes: new TextEncoder().encode(shown).length,
        error: `initialize refused: ${initError}`,
      });
    }

    // A stateless server mints no session; then there is simply no header to echo.
    const sessionId = init.headers.get('mcp-session-id');
    const session: Record<string, string> = {
      ...headers,
      'MCP-Protocol-Version': MCP_PROTOCOL_VERSION,
      ...(sessionId ? { 'Mcp-Session-Id': sessionId } : {}),
    };

    // 2. notifications/initialized - a notification, so no id and no reply.
    await post(endpoint, session, { jsonrpc: '2.0', method: 'notifications/initialized' }, controller.signal);

    // 3. the call the user actually asked for.
    const call = await post(
      endpoint,
      session,
      { jsonrpc: '2.0', id: 2, method, params },
      controller.signal
    );

    // 4. Close the session. Best-effort: a server that does not implement DELETE
    //    is not a failure of the call that already succeeded.
    if (sessionId) {
      try {
        await fetch(endpoint, { method: 'DELETE', headers: session, signal: controller.signal });
      } catch {
        // Nothing to do, and nothing the user needs to see.
      }
    }

    const pretty =
      call.json !== undefined ? JSON.stringify(call.json, null, 2) : call.raw;

    return NextResponse.json({
      status: call.status,
      statusText: call.statusText,
      headers: Object.fromEntries(call.headers.entries()),
      body: pretty,
      // Always report JSON: the SSE framing is a transport detail we unwrapped,
      // and reporting text/event-stream would send the viewer to its Raw tab.
      contentType: 'application/json',
      timeMs: Date.now() - started,
      sizeBytes: new TextEncoder().encode(pretty).length,
      // A tool that raises is a successful HTTP call carrying isError, and that
      // is the body's business. Only a protocol-level error is surfaced here.
      error: rpcError(call.json) ?? undefined,
    });
  } catch (err) {
    const aborted = err instanceof Error && err.name === 'AbortError';
    return errorResult(
      aborted
        ? `MCP call timed out after ${TIMEOUT_MS / 1000}s`
        : err instanceof Error
          ? err.message
          : 'MCP call failed',
      started
    );
  } finally {
    clearTimeout(timer);
  }
}
