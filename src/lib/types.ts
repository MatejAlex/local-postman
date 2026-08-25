// Type definitions for local-postman

export const APP_VERSION = 'v1.5';

export type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE' | 'HEAD' | 'OPTIONS';

export const METHODS: Method[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

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
