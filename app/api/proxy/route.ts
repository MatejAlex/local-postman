import { NextRequest, NextResponse } from 'next/server';

// Server-side request forwarder. Running the fetch here (not in the browser)
// sidesteps CORS so the client can hit arbitrary APIs, like real Postman.
//
// Security model: this is a local developer tool, so reaching localhost and
// internal dev servers is a *feature*, not a bug — we intentionally do NOT
// block private/loopback IPs. The real risk is a third-party web page POSTing
// to this route to weaponise the user's machine as a proxy (drive-by SSRF), so
// we require the request to originate from this app's own UI (same-origin).
// We also follow redirects manually and strip credentials on cross-origin hops
// so an upstream 30x cannot leak Authorization/Cookie to another host.

const TIMEOUT_MS = 30_000;
const MAX_REDIRECTS = 5;
const SENSITIVE_HEADERS = ['authorization', 'cookie', 'proxy-authorization'];

interface ProxyPayload {
  url: string;
  method: string;
  headers?: Record<string, string>;
  body?: string;
}

function errorResult(message: string, started: number) {
  return NextResponse.json({
    status: 0,
    statusText: '',
    headers: {},
    body: '',
    contentType: '',
    timeMs: Date.now() - started,
    sizeBytes: 0,
    error: message,
  });
}

/** Only allow calls that the browser marks as originating from this same app. */
function isSameOrigin(req: NextRequest): boolean {
  // Sec-Fetch-Site is set by the browser and is a forbidden header (page JS
  // cannot forge it). same-origin = our own UI; none = direct/non-browser.
  const site = req.headers.get('sec-fetch-site');
  if (site) return site === 'same-origin' || site === 'none';

  // Fallback for browsers without Fetch Metadata: compare Origin to Host.
  const origin = req.headers.get('origin');
  if (origin) {
    try {
      return new URL(origin).host === req.headers.get('host');
    } catch {
      return false;
    }
  }
  // No Origin and no Sec-Fetch-Site => not a cross-site browser request.
  return true;
}

function stripSensitive(headers: Record<string, string>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(headers).filter(([k]) => !SENSITIVE_HEADERS.includes(k.toLowerCase()))
  );
}

/**
 * Follow redirects by hand so we can drop credentials when a hop crosses
 * origins. Mirrors browser semantics closely enough for an API client:
 * 303 (and POST on 301/302) downgrade to GET; 307/308 preserve method+body.
 */
async function fetchFollowing(
  startUrl: string,
  method: string,
  headers: Record<string, string>,
  body: string | undefined,
  signal: AbortSignal
): Promise<Response> {
  let url = new URL(startUrl);
  let currentMethod = method;
  let currentBody = body;
  let currentHeaders = { ...headers };

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const resp = await fetch(url, {
      method: currentMethod,
      headers: currentHeaders,
      body:
        currentMethod === 'GET' || currentMethod === 'HEAD' ? undefined : currentBody,
      signal,
      redirect: 'manual',
    });

    const location = resp.headers.get('location');
    const isRedirect = resp.status >= 300 && resp.status < 400 && location;
    if (!isRedirect) return resp;
    if (hop === MAX_REDIRECTS) throw new Error('Too many redirects');

    const next = new URL(location, url);
    if (!/^https?:$/.test(next.protocol)) throw new Error('Redirect to non-http(s) URL');

    if (next.protocol !== url.protocol || next.host !== url.host) {
      // Cross-origin hop: never carry the original credentials onward.
      currentHeaders = stripSensitive(currentHeaders);
    }

    if (resp.status === 303 || ((resp.status === 301 || resp.status === 302) && currentMethod === 'POST')) {
      currentMethod = 'GET';
      currentBody = undefined;
    }
    url = next;
  }

  // Unreachable, but keeps the type checker happy.
  throw new Error('Too many redirects');
}

export async function POST(req: NextRequest) {
  const started = Date.now();

  if (!isSameOrigin(req)) {
    return NextResponse.json(
      { error: 'Cross-origin requests to the proxy are not allowed.' },
      { status: 403 }
    );
  }

  let payload: ProxyPayload;
  try {
    payload = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid request payload' }, { status: 400 });
  }

  const { url, method, headers = {}, body } = payload;

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

  try {
    const upstream = await fetchFollowing(parsed.toString(), method, headers, body, controller.signal);

    const text = await upstream.text();
    const respHeaders: Record<string, string> = {};
    upstream.headers.forEach((value, key) => {
      respHeaders[key] = value;
    });

    return NextResponse.json({
      status: upstream.status,
      statusText: upstream.statusText,
      headers: respHeaders,
      body: text,
      contentType: upstream.headers.get('content-type') || '',
      timeMs: Date.now() - started,
      sizeBytes: new TextEncoder().encode(text).length,
    });
  } catch (err) {
    const aborted = err instanceof Error && err.name === 'AbortError';
    return errorResult(
      aborted
        ? `Request timed out after ${TIMEOUT_MS / 1000}s`
        : err instanceof Error
          ? err.message
          : 'Request failed',
      started
    );
  } finally {
    clearTimeout(timer);
  }
}
