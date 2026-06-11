import { NextRequest, NextResponse } from 'next/server';

// Server-side request forwarder. Running the fetch here (not in the browser)
// sidesteps CORS so the client can hit arbitrary APIs, like real Postman.

const TIMEOUT_MS = 30_000;

interface ProxyPayload {
  url: string;
  method: string;
  headers?: Record<string, string>;
  body?: string;
}

export async function POST(req: NextRequest) {
  const started = Date.now();
  let payload: ProxyPayload;
  try {
    payload = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid request payload' }, { status: 400 });
  }

  const { url, method, headers = {}, body } = payload;

  if (!url || !/^https?:\/\//i.test(url)) {
    return NextResponse.json(
      { error: 'URL must be an absolute http(s) address.' },
      { status: 200 }
    );
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const upstream = await fetch(url, {
      method,
      headers,
      body: method === 'GET' || method === 'HEAD' ? undefined : body,
      signal: controller.signal,
      redirect: 'follow',
    });

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
    return NextResponse.json({
      status: 0,
      statusText: '',
      headers: {},
      body: '',
      contentType: '',
      timeMs: Date.now() - started,
      sizeBytes: 0,
      error: aborted
        ? `Request timed out after ${TIMEOUT_MS / 1000}s`
        : err instanceof Error
          ? err.message
          : 'Request failed',
    });
  } finally {
    clearTimeout(timer);
  }
}
