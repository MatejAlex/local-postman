// Client-side wrappers around the /api/storage and /api/proxy routes.

import type { ApiResponse, Environment, HistoryItem, RequestGroup, ResolvedRequest } from './types';

interface StorageSnapshot {
  environments: Environment[];
  groups: RequestGroup[];
  history: HistoryItem[];
}

const HISTORY_LIMIT = 50;

export async function loadAll(): Promise<StorageSnapshot> {
  const res = await fetch('/api/storage', { cache: 'no-store' });
  if (!res.ok) return { environments: [], groups: [], history: [] };
  const data = await res.json();
  return {
    environments: data.environments ?? [],
    groups: data.groups ?? [],
    history: data.history ?? [],
  };
}

async function put(name: string, data: unknown) {
  await fetch('/api/storage', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, data }),
  });
}

async function remove(name: string) {
  await fetch(`/api/storage?name=${encodeURIComponent(name)}`, { method: 'DELETE' });
}

export const saveGroup = (g: RequestGroup) => put(g.id, g);
export const deleteGroup = (id: string) => remove(id);

export const saveEnvironment = (e: Environment) => put(e.id, e);
export const deleteEnvironment = (id: string) => remove(id);

export async function appendHistory(item: HistoryItem, current: HistoryItem[]): Promise<HistoryItem[]> {
  const next = [item, ...current].slice(0, HISTORY_LIMIT);
  await put('history', next);
  return next;
}

export async function clearHistory(): Promise<void> {
  await put('history', []);
}

/** Send an already-resolved request through the proxy and return the structured response. */
export async function sendResolved(resolved: ResolvedRequest): Promise<ApiResponse> {
  try {
    const res = await fetch('/api/proxy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(resolved),
    });
    return (await res.json()) as ApiResponse;
  } catch (err) {
    return {
      status: 0,
      statusText: '',
      headers: {},
      body: '',
      contentType: '',
      timeMs: 0,
      sizeBytes: 0,
      error: err instanceof Error ? err.message : 'Network error',
    };
  }
}
