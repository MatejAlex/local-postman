## Features Implemented (v1.0)

1. **Collections of requests** — requests are organized into named groups; groups and requests can be added, renamed (double-click), and deleted.
Deleting a collection asks for confirmation first, naming it and how many requests go with it; deleting a single request does not.
Each collection has a ⚙ panel holding its **variables** and its **auth**, and the ⚙ turns accent-coloured once either is set.
2. **Environments** — named profiles (e.g. Development, Production) each with a color and a list of `{{variable}}` key/values. One environment is active globally; its color tints the header. Variables are substituted into the URL, query params, headers, and body at send time.
3. **Collection variables** — the same `{{key}}` mechanism scoped to one collection, which is where a per-collection access token belongs (`Authorization: Bearer {{token}}`).
**The active environment wins on a name clash**, so a collection-wide default can be overridden per environment; this is the precedence Postman uses, and `requestVariables()` in `src/lib/utils.ts` is the single place it is decided.
The settings panel flags any collection variable the environment is currently shadowing.
4. **Request builder** — method, URL with `{{variable}}` support, and tabs for query Params, Headers, and Body (None / JSON / Raw, with Beautify for JSON).
5. **Server proxy** — requests are forwarded through `/api/proxy` (server-side fetch) so arbitrary APIs work without browser CORS errors. Network and timeout failures return a structured error instead of crashing.
6. **Rich response viewer** — status, time, size, and tabs for Pretty / Raw / Headers, plus copy-to-clipboard.
Pretty indents JSON, HTML and XML.
An HTML body also gets a **Preview** tab that renders it in a sandboxed iframe (no `allow-scripts`, no `allow-same-origin`), which is what makes an ORDS/APEX error page readable; it opens on that tab by default.
7. **Request history** — the last 50 sends are recorded in the History panel, each row showing the request's name, its status and two buttons: 🔍 opens the sent request and its response in a modal, ↻ sends it again.
History recorded before v1.2 has no name and shows "Unnamed request".
8. **File-based storage** — environments, groups, and history are persisted as JSON via `/api/storage` (one file per env/group, plus `history.json`), in `~/.local-postman` rather than inside the repo.
9. **Theming** — three modes (Dark Grey default → Dark → Light) cycled via the header icon, persisted to localStorage.

## Architecture

- `app/api/proxy/route.ts` — POST: server-side request forwarder (kills CORS, 30s timeout).
- `app/api/storage/route.ts` — GET/PUT/DELETE: reads/writes `~/.local-postman/*.json` (path-traversal guarded), seeded from the repo's `storage/` on a first run.
- `src/lib/` — `types.ts`, `utils.ts` (variable substitution + formatting), `storage.ts` (client API wrappers), `theme.tsx`.
- `src/components/` — `Sidebar`, `EnvironmentManager`, `RequestBuilder`, `KeyValueEditor`, `ResponseViewer`, `HistoryPanel`, `HistoryDetail`, `ConfirmDialog`.
`HistoryDetail` reuses `ResponseViewer` for the response pane, so a stored response formats exactly like a fresh one.
`resolveRequest(req, group, env)` takes the collection rather than a pre-computed auth, so the variables and the auth it applies always come from the same place.

## Development Notes

- The application runs on port 3010 (`npm run dev` / `npm run start`).
- Both scripts set `NODE_OPTIONS=--use-system-ca`.
Node ships its own CA bundle and ignores the macOS keychain, so without this any host behind a private CA (an internal O2 endpoint, a corporate MITM proxy) fails the TLS handshake and the proxy reports it as a bare `fetch failed`.
- Runtime storage lives in `~/.local-postman`, overridable with `LOCAL_POSTMAN_DIR`.
It sits outside the repo on purpose: history records whatever headers were sent, credentials included, and a `.gitignore` entry protects git but not a zip, a backup, or `git clean -xdf`.
The repo's `storage/` is seed-only. `env-1.json` and `group-1.json` are committed, point at `https://jsonplaceholder.typicode.com`, and are copied into the storage dir when it has no JSON in it yet, so a fresh checkout can send a working request immediately.
- `APP_VERSION` is defined in `src/lib/types.ts` and shown in the header; keep it in sync with `package.json`.
