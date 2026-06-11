# local-postman v1.0 — Rebuild Design

Date: 2026-06-11

## Problem

The initial agent left the project unbuildable and hollow:

- `RequestBuilder.tsx` / `EnvironmentManager.tsx` import types from a non-existent `./types`
  path and omit `'use client'`.
- `app/page.tsx` renders `<EnvironmentManager>` without its required `onUpdateEnvironment`
  prop; the variables editor can never add a variable.
- `src/app/page.tsx` is a broken orphan duplicate that conflicts with the real route.
- Storage uses `localStorage` despite a `storage/` folder of seed JSON that is never loaded,
  contradicting the AGENTS.md "file-based storage" claim.
- Browser-side `fetch` to arbitrary URLs fails on CORS; `response.json()` crashes on
  non-JSON; there is no error UI.
- No theme system, version constant, query params, history, or rename/delete.

This is a rebuild, not a finish.

## Goals

A usable local Postman-style API client:

1. Build cleanly, no dead/duplicate code.
2. Server-side file storage in `storage/*.json` via API routes (data survives across browsers).
3. Server proxy so real APIs work without CORS errors.
4. Environments as the single source of profiles (Dev/Prod) with editable variables + color;
   the muddled per-request prod/dev flag is removed.
5. Core request builder, rich response viewer, request history, and full manage/rename/delete.
6. Three-mode theme per global standard, visible `APP_VERSION`.

## Architecture

```
app/
  layout.tsx            fix metadata, mount ThemeProvider
  page.tsx              three-pane orchestrator
  globals.css           theme tokens (Light / Dark Grey / Dark)
  api/
    proxy/route.ts      POST: forward a request server-side, return structured result
    storage/route.ts    GET/PUT/DELETE: read/write storage/*.json
src/
  lib/types.ts          Environment, ApiRequest, RequestGroup, ApiResponse, HistoryItem
  lib/storage.ts        client fns -> /api/storage  (replaces localStorage api.ts)
  lib/proxy.ts          client fn -> /api/proxy
  lib/variables.ts      {{var}} substitution across url/headers/body
  lib/theme.tsx         3-mode theme context + rotating Sun/Cloud/Moon icon
  components/
    Sidebar.tsx
    EnvironmentManager.tsx
    RequestBuilder.tsx   method, URL, tabs: Params / Headers / Body
    KeyValueEditor.tsx   reusable enabled/key/value rows
    ResponseViewer.tsx   status/time/size + tabs: Pretty / Raw / Headers
    HistoryPanel.tsx
```

## Data Model

- `KeyValue { key: string; value: string; enabled: boolean }`
- `Environment { id; name; color; variables: KeyValue[] }` — active environment is global;
  its color tints the top bar.
- `ApiRequest { id; name; method; url; params: KeyValue[]; headers: KeyValue[]; body?: string;
  bodyType: 'none' | 'json' | 'raw' }`
- `RequestGroup { id; name; requests: ApiRequest[] }`
- `ApiResponse { status; statusText; headers: Record<string,string>; body: string;
  contentType: string; timeMs: number; sizeBytes: number; error?: string }`
- `HistoryItem { id; timestamp; method; url; response: ApiResponse }`

Persistence layout in `storage/`:
- `group-<id>.json` per group
- `env-<id>.json` per environment
- `history.json` (capped to most recent N, e.g. 50)

## Request Flow

1. User selects a request, edits it (edits autosave back to the group file, debounced).
2. Send: client substitutes `{{vars}}` from the active environment across url/enabled
   headers/body via `variables.ts`.
3. Client POSTs the resolved request to `/api/proxy`.
4. Server performs `fetch` with a timeout, captures status/headers/body/timing/size, and
   returns a structured `ApiResponse` (network/timeout failures become `error`, never a throw).
5. `ResponseViewer` renders; non-JSON bodies show as raw text; JSON is pretty-printed.
6. The send is appended to `history.json`.

## Theme

Per global standard: rotate Dark Grey (default) → Dark → Light on icon click
(Sun = light, Cloud = dark-grey, Moon = dark). All colors via CSS variables in `globals.css`.
`APP_VERSION = "v1.0"` rendered in the header; `package.json` version set to `1.0.0`.

## Error Handling

- Proxy: try/catch with `AbortController` timeout → structured `{ error }` result.
- Non-JSON responses render as raw text (content-type aware).
- Invalid/empty URL flagged inline before send.
- Storage API: validates ids, guards against path traversal (only `storage/` basenames).

## Testing

- `npm run build` must pass with zero type errors.
- Manual smoke: create env, create group + request with `{{base_url}}/users`, send against a
  public API (e.g. httpbin), confirm response viewer + history populate, confirm files written
  to `storage/`, confirm theme rotation and persistence.

## Out of Scope (YAGNI for v1.0)

- Auth helpers beyond raw headers, request scripting/tests, import/export collections,
  cookies jar, multi-tab requests. These can follow in later versions.
