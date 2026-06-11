// Utility functions

import type { ApiRequest, Environment, KeyValue } from './types';

/** Build a flat variable map from an environment's enabled variables. */
export function variableMap(env: Environment | null): Record<string, string> {
  const map: Record<string, string> = {};
  if (!env) return map;
  for (const v of env.variables) {
    if (v.enabled && v.key.trim()) map[v.key] = v.value;
  }
  return map;
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

/** Resolve a request into a concrete URL / headers / body ready for the proxy. */
export function resolveRequest(req: ApiRequest, env: Environment | null) {
  const vars = variableMap(env);
  const url = buildUrl(req.url, req.params, vars);

  const headers: Record<string, string> = {};
  for (const h of req.headers) {
    if (h.enabled && h.key.trim()) headers[substitute(h.key, vars)] = substitute(h.value, vars);
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
