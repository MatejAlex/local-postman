// Type definitions for local-postman

export const APP_VERSION = 'v1.0';

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

export interface ApiRequest {
  id: string;
  name: string;
  method: Method;
  url: string;
  params: KeyValue[];
  headers: KeyValue[];
  body: string;
  bodyType: BodyType;
}

export interface RequestGroup {
  id: string;
  name: string;
  requests: ApiRequest[];
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
  method: Method;
  url: string;
  resolved: ResolvedRequest;
  response: ApiResponse;
}

export function emptyKeyValue(): KeyValue {
  return { key: '', value: '', enabled: true };
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
  };
}

export function newGroup(): RequestGroup {
  return {
    id: `group-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    name: 'New Group',
    requests: [],
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
