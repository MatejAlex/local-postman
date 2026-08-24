// Utility functions

import type { ApiRequest, BasicAuth, CollectionAuth, Environment, KeyValue, RequestGroup } from './types';
import { collectionAuthOf, collectionVariablesOf, requestAuthOf } from './types';

/** Flatten key/value rows into a lookup, skipping the disabled and the unnamed. */
export function variableMapOf(rows: KeyValue[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (const row of rows) {
    if (row.enabled && row.key.trim()) map[row.key] = row.value;
  }
  return map;
}

/** Build a flat variable map from an environment's enabled variables. */
export function variableMap(env: Environment | null): Record<string, string> {
  return env ? variableMapOf(env.variables) : {};
}

/** Build a flat variable map from a collection's own enabled variables. */
export function collectionVariableMap(group: RequestGroup | null): Record<string, string> {
  return group ? variableMapOf(collectionVariablesOf(group)) : {};
}

/**
 * Everything a request in this collection can reference.
 * The environment wins on a name clash, so one collection-wide default can be
 * overridden per environment. This is the precedence Postman uses.
 */
export function requestVariables(
  group: RequestGroup | null,
  env: Environment | null
): Record<string, string> {
  return { ...collectionVariableMap(group), ...variableMap(env) };
}

/** Replace every {{key}} occurrence using the variable map. */
export function substitute(text: string, vars: Record<string, string>): string {
  return text.replace(/\{\{\s*([\w.-]+)\s*\}\}/g, (whole, key) =>
    Object.prototype.hasOwnProperty.call(vars, key) ? vars[key] : whole
  );
}

/** Append enabled query params to a URL string. */
export function buildUrl(url: string, params: KeyValue[], vars: Record<string, string>): string {
  const resolved = substitute(url, vars);
  const active = params.filter((p) => p.enabled && p.key.trim());
  if (active.length === 0) return resolved;

  const sep = resolved.includes('?') ? '&' : '?';
  const qs = active
    .map(
      (p) =>
        `${encodeURIComponent(substitute(p.key, vars))}=${encodeURIComponent(substitute(p.value, vars))}`
    )
    .join('&');
  return `${resolved}${sep}${qs}`;
}

/** Base64 for UTF-8 text. Plain btoa throws on anything outside Latin-1. */
function toBase64(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

/**
 * The Authorization value for a credential pair, or null when nothing is filled in.
 * With base64 off the credentials go out verbatim, which is not valid HTTP Basic but
 * is useful for seeing what a gateway actually receives.
 */
export function basicAuthHeader(basic: BasicAuth, vars: Record<string, string>): string | null {
  const username = substitute(basic.username, vars);
  const password = substitute(basic.password, vars);
  if (username === '' && password === '') {
    return null;
  }
  const pair = `${username}:${password}`;
  return `Basic ${basic.base64 ? toBase64(pair) : pair}`;
}

/** The request's own setting wins; 'inherit' falls back to the collection, 'none' sends nothing. */
export function authHeaderFor(
  req: ApiRequest,
  collectionAuth: CollectionAuth | null,
  vars: Record<string, string>
): string | null {
  const auth = requestAuthOf(req);
  if (auth.mode === 'none') {
    return null;
  }
  if (auth.mode === 'basic') {
    return basicAuthHeader(auth.basic, vars);
  }
  if (collectionAuth && collectionAuth.mode === 'basic') {
    return basicAuthHeader(collectionAuth.basic, vars);
  }
  return null;
}

/** Resolve a request into a concrete URL / headers / body ready for the proxy. */
export function resolveRequest(req: ApiRequest, group: RequestGroup | null, env: Environment | null) {
  const vars = requestVariables(group, env);
  const collectionAuth = group ? collectionAuthOf(group) : null;
  const url = buildUrl(req.url, req.params, vars);

  const headers: Record<string, string> = {};
  for (const h of req.headers) {
    if (h.enabled && h.key.trim()) headers[substitute(h.key, vars)] = substitute(h.value, vars);
  }

  // An Authorization header typed by hand wins over the auth panels.
  const hasManualAuth = Object.keys(headers).some((k) => k.toLowerCase() === 'authorization');
  if (!hasManualAuth) {
    const authValue = authHeaderFor(req, collectionAuth, vars);
    if (authValue) {
      headers['Authorization'] = authValue;
    }
  }

  let body: string | undefined;
  if (req.method !== 'GET' && req.method !== 'HEAD' && req.bodyType !== 'none') {
    body = substitute(req.body, vars);
    if (req.bodyType === 'json' && !Object.keys(headers).some((k) => k.toLowerCase() === 'content-type')) {
      headers['Content-Type'] = 'application/json';
    }
  }

  return { url, method: req.method, headers, body };
}

export function formatTime(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)} ms`;
  return `${(ms / 1000).toFixed(2)} s`;
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

export function statusColor(status: number): string {
  if (status >= 200 && status < 300) return 'var(--ok)';
  if (status >= 300 && status < 400) return 'var(--info)';
  if (status >= 400 && status < 500) return 'var(--warn)';
  if (status >= 500) return 'var(--danger)';
  return 'var(--muted-fg)';
}

export function prettyJson(body: string): string {
  try {
    return JSON.stringify(JSON.parse(body), null, 2);
  } catch {
    return body;
  }
}

const VOID_TAGS = new Set([
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img',
  'input', 'link', 'meta', 'param', 'source', 'track', 'wbr',
]);

/** Their content is text, not markup, so it is copied through instead of re-indented. */
const RAW_TEXT_TAGS = new Set(['script', 'style', 'pre', 'textarea']);

/** HTML lets you omit these closing tags: opening a listed sibling closes the previous one. */
const IMPLICIT_CLOSE: Record<string, string[]> = {
  li: ['li'],
  p: ['p'],
  dt: ['dt', 'dd'],
  dd: ['dt', 'dd'],
  tr: ['tr'],
  td: ['td', 'th'],
  th: ['td', 'th'],
  option: ['option'],
};

/**
 * Re-indent HTML or XML so a wall-of-markup error page can be read.
 * This is a source formatter, not a parser: it never drops content, but badly
 * nested markup comes out with odd indentation.
 */
export function prettyMarkup(markup: string): string {
  const lines: string[] = [];
  const openTags: string[] = [];
  let cursor = 0;

  const push = (text: string) => {
    lines.push(text === '' ? '' : '  '.repeat(Math.min(openTags.length, 30)) + text);
  };

  while (cursor < markup.length) {
    const tagStart = markup.indexOf('<', cursor);
    if (tagStart === -1) {
      push(markup.slice(cursor).trim());
      break;
    }

    const text = markup.slice(cursor, tagStart).trim();
    if (text !== '') {
      push(text);
    }

    if (markup.startsWith('<!--', tagStart)) {
      const commentEnd = markup.indexOf('-->', tagStart);
      const stop = commentEnd === -1 ? markup.length : commentEnd + 3;
      push(markup.slice(tagStart, stop).trim());
      cursor = stop;
      continue;
    }

    const tagEnd = markup.indexOf('>', tagStart);
    if (tagEnd === -1) {
      push(markup.slice(tagStart).trim());
      break;
    }

    const tag = markup.slice(tagStart, tagEnd + 1);
    const name = tagNameOf(tag);
    cursor = tagEnd + 1;

    if (tag.startsWith('</')) {
      const openedAt = openTags.lastIndexOf(name);
      if (openedAt !== -1) {
        openTags.length = openedAt;
      }
      push(tag);
      continue;
    }

    const previous = openTags[openTags.length - 1];
    if (previous && (IMPLICIT_CLOSE[name] ?? []).includes(previous)) {
      openTags.pop();
    }
    push(tag);

    const closesItself =
      tag.endsWith('/>') || tag.startsWith('<!') || tag.startsWith('<?') || VOID_TAGS.has(name);
    if (closesItself) {
      continue;
    }
    openTags.push(name);

    if (RAW_TEXT_TAGS.has(name)) {
      const closeAt = markup.toLowerCase().indexOf(`</${name}`, cursor);
      const stop = closeAt === -1 ? markup.length : closeAt;
      for (const line of dedent(markup.slice(cursor, stop))) {
        push(line);
      }
      cursor = stop;
    }
  }

  return lines.join('\n');
}

function tagNameOf(tag: string): string {
  const match = /^<\/?\s*([a-zA-Z0-9:_-]+)/.exec(tag);
  return match ? match[1].toLowerCase() : '';
}

/** Strip the blank edges and the shared leading whitespace off a raw text block. */
function dedent(block: string): string[] {
  const lines = block.split('\n').map((line) => line.replace(/\s+$/, ''));
  while (lines.length > 0 && lines[0] === '') {
    lines.shift();
  }
  while (lines.length > 0 && lines[lines.length - 1] === '') {
    lines.pop();
  }

  let shared = Infinity;
  for (const line of lines) {
    if (line !== '') {
      shared = Math.min(shared, line.length - line.trimStart().length);
    }
  }
  if (shared === Infinity) {
    return lines;
  }
  return lines.map((line) => line.slice(shared));
}
