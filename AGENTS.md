## Features Implemented (v1.0)

1. **Collections of requests** — requests are organized into named groups; groups and requests can be added, renamed (double-click), and deleted.
2. **Environments** — named profiles (e.g. Development, Production) each with a color and a list of `{{variable}}` key/values. One environment is active globally; its color tints the header. Variables are substituted into the URL, query params, headers, and body at send time.
3. **Request builder** — method, URL with `{{variable}}` support, and tabs for query Params, Headers, and Body (None / JSON / Raw, with Beautify for JSON).
4. **Server proxy** — requests are forwarded through `/api/proxy` (server-side fetch) so arbitrary APIs work without browser CORS errors. Network and timeout failures return a structured error instead of crashing.
5. **Rich response viewer** — status, time, size, and tabs for Pretty (JSON) / Raw / Headers, plus copy-to-clipboard.
6. **Request history** — the last 50 sends are recorded and re-runnable from the History panel.
7. **File-based storage** — environments, groups, and history are persisted as JSON in `storage/` via `/api/storage` (one file per env/group, plus `history.json`).
8. **Theming** — three modes (Dark Grey default → Dark → Light) cycled via the header icon, persisted to localStorage.

## Architecture

- `app/api/proxy/route.ts` — POST: server-side request forwarder (kills CORS, 30s timeout).
- `app/api/storage/route.ts` — GET/PUT/DELETE: reads/writes `storage/*.json` (path-traversal guarded).
- `src/lib/` — `types.ts`, `utils.ts` (variable substitution + formatting), `storage.ts` (client API wrappers), `theme.tsx`.
- `src/components/` — `Sidebar`, `EnvironmentManager`, `RequestBuilder`, `KeyValueEditor`, `ResponseViewer`, `HistoryPanel`.

## Development Notes

- The application runs on port 3010 (`npm run dev` / `npm run start`).
- Storage lives in `storage/`. Seed files `env-1.json` and `group-1.json` are committed and point at `https://jsonplaceholder.typicode.com` so a fresh checkout can send a working request immediately. `storage/history.json` is gitignored.
- `APP_VERSION` is defined in `src/lib/types.ts` and shown in the header; keep it in sync with `package.json`.
