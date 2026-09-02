// Type definitions for local-postman

import type { McpConfig, McpMethod } from './mcp';
import { emptyMcpConfig } from './mcp';

export const APP_VERSION = 'v1.6';

export type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';

export const METHODS: Method[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

/**
 * An MCP request is still an HTTP POST, so it keeps `method`, `url` and
 * `headers` and only swaps what goes in the body. Making it a kind rather than
 * a separate entity is what lets collections, variables, auth and history stay
 * one implementation instead of two.
 */
export type RequestKind = 'http' | 'mcp';

export type BodyType = 'none' | 'json' | 'raw';

export interface KeyValue {
  key: string;
  value: string;
  enabled: boolean;
}

export interface Environment {
  id: string;
  name: string;
  color: string; // hex
  variables: KeyValue[];
}

export type AuthMode = 'none' | 'basic';

/** A request may also defer to its collection, which is the default. */
export type RequestAuthMode = 'inherit' | AuthMode;

export interface BasicAuth {
  username: string;
  password: string;
  /** Standard HTTP Basic, and what ORDS expects. Off sends the raw `user:pass` instead. */
  base64: boolean;
}

export interface CollectionAuth {
  mode: AuthMode;
  basic: BasicAuth;
}

export interface RequestAuth {
  mode: RequestAuthMode;
  basic: BasicAuth;
}

export interface ApiRequest {
  id: string;
  name: string;
  method: Method;
  url: string;
  params: KeyValue[];
  headers: KeyValue[];
  body: string;
  bodyType: BodyType;
  auth?: RequestAuth; // absent in collections saved before v1.1
  kind?: RequestKind; // absent in collections saved before v1.6, meaning 'http'
  mcp?: McpConfig; // only meaningful when kind === 'mcp'
}

export interface RequestGroup {
  id: string;
  name: string;
  requests: ApiRequest[];
  auth?: CollectionAuth; // absent in collections saved before v1.1
  variables?: KeyValue[]; // absent in collections saved before v1.3
}

export interface ApiResponse {
  status: number;
  statusText: string;
  headers: Record<string, string>;
  body: string;
  contentType: string;
  timeMs: number;
  sizeBytes: number;
  error?: string;
}

export interface ResolvedRequest {
  url: string;
  method: Method;
  headers: Record<string, string>;
  body?: string;
  /**
   * Present when this resolved to an MCP call. It carries the JSON-RPC method
   * and params so a history entry replays as MCP rather than as a bare POST,
   * which is the whole reason it lives on the resolved request and not just in
   * the builder.
   */
  mcp?: { method: McpMethod; params: Record<string, unknown> };
}

export interface HistoryItem {
  id: string;
  timestamp: number;
  name?: string; // absent in history recorded before v1.2
  method: Method;
  url: string;
  resolved: ResolvedRequest;
  response: ApiResponse;
}

export function emptyKeyValue(): KeyValue {
  return { key: '', value: '', enabled: true };
}

export function emptyBasicAuth(): BasicAuth {
  return { username: '', password: '', base64: true };
}

/** The request's own auth setting, defaulting to inheriting the collection's. */
export function requestAuthOf(req: ApiRequest): RequestAuth {
  return req.auth ?? { mode: 'inherit', basic: emptyBasicAuth() };
}

export function collectionAuthOf(group: RequestGroup): CollectionAuth {
  return group.auth ?? { mode: 'none', basic: emptyBasicAuth() };
}

export function collectionVariablesOf(group: RequestGroup): KeyValue[] {
  return group.variables ?? [];
}

/** Everything saved before v1.6 is an ordinary HTTP request. */
export function requestKindOf(req: ApiRequest): RequestKind {
  return req.kind ?? 'http';
}

export function mcpConfigOf(req: ApiRequest): McpConfig {
  return req.mcp ?? emptyMcpConfig();
}

/** What the method column shows. MCP requests are POSTs but never read as one. */
export function badgeOf(req: Pick<ApiRequest, 'method' | 'kind'>): string {
  return (req.kind ?? 'http') === 'mcp' ? 'MCP' : req.method;
}

export function newRequest(): ApiRequest {
  return {
    id: `req-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    name: 'New Request',
    method: 'GET',
    url: '',
    params: [],
    headers: [],
    body: '',
    bodyType: 'none',
    auth: { mode: 'inherit', basic: emptyBasicAuth() },
  };
}

export function newMcpRequest(): ApiRequest {
  return {
    ...newRequest(),
    name: 'New MCP Request',
    // The transport is always a POST; only the body differs from an HTTP request.
    method: 'POST',
    kind: 'mcp',
    mcp: emptyMcpConfig(),
  };
}

export function newGroup(): RequestGroup {
  return {
    id: `group-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    name: 'New Group',
    requests: [],
    auth: { mode: 'none', basic: emptyBasicAuth() },
    variables: [],
  };
}

export function newEnvironment(): Environment {
  return {
    id: `env-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    name: 'New Environment',
    color: '#6366f1',
    variables: [],
  };
}
