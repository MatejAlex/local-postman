## Features Implemented (v1.0)

1. **Collections of requests** — requests are organized into named groups; groups and requests can be added, renamed (double-click), and deleted.
Deleting a collection asks for confirmation first, naming it and how many requests go with it; deleting a single request does not.
Each collection has a ⚙ panel holding its **variables** and its **auth**, and the ⚙ turns accent-coloured once either is set.
2. **Environments** — named profiles (e.g. Development, Production) each with a color and a list of `{{variable}}` key/values. One environment is active globally; its color tints the header. Variables are substituted into the URL, query params, headers, and body at send time.
3. **Collection variables** — the same `{{key}}` mechanism scoped to one collection, which is where a per-collection access token belongs (`Authorization: Bearer {{token}}`).
**Clicking an environment in the sidebar list activates it**, and the active row is highlighted.
Until v1.6 that list was display-only and only the dropdown selected: you clicked an environment, nothing moved, and every `{{variable}}` quietly kept resolving against the environment the dropdown still named. Substitution was never broken; the picker was.
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
10. **Shareable collections (v1.5)** — a `group-*.json` never contains a password, so it can be handed to a colleague as it sits.
Basic-auth passwords live in `~/.local-postman/secrets.json` instead, keyed by collection id or `collectionId/requestId`.
Nothing about using the app changes: the password box is typed into as before, and the storage route does the split on the way past.

11. **MCP requests (v1.6)** — a request has a **kind**, `http` or `mcp`, and an MCP one talks to an MCP server over Streamable HTTP.
It keeps the URL, the headers, the auth panel and `{{variable}}` substitution; it swaps Params and Body for a single **MCP** tab holding the method, the target and a JSON arguments box.
Seven methods: `tools/list`, `tools/call`, `prompts/list`, `prompts/get`, `resources/list`, `resources/read`, `ping`.
Add one from the collection header's **M** button.
**There is no connect step.** Every send runs the whole `initialize` → `notifications/initialized` → call → `DELETE` sequence and throws the session away, so a result never depends on what you clicked earlier. That costs a round-trip and buys statelessness; a full call against a local server lands in well under 200 ms.
Deliberately absent, and the reason this is not a fork of the reference inspector: no OAuth dance, no server-launching, no connection pane, no notifications/roots/sampling.

## Architecture

- `app/api/mcp/route.ts` — POST: the MCP client. One MCP call is three HTTP requests behind a session handshake, which is why it cannot be `/api/proxy` with a different body. It understands both response framings (plain JSON and SSE), unwraps the SSE one, and reports `application/json` either way so the viewer opens on Pretty. A JSON-RPC error becomes the response's `error` while the payload still fills the body; a tool that returns `isError` is a successful call and is left alone.
- `src/lib/mcp.ts` — the method catalogue, which methods need a target or take arguments, and `mcpParamsFor()`, which turns a config into JSON-RPC params **or** an error. Bad JSON is caught here so the message names the box the user is looking at, and such a request never reaches the network or the history.
- `app/api/proxy/route.ts` — POST: server-side request forwarder (kills CORS, 30s timeout).
- `app/api/storage/route.ts` — GET/PUT/DELETE: reads/writes `~/.local-postman/*.json` (path-traversal guarded), seeded from the repo's `storage/` on a first run.
It is also the only place that knows about `secrets.json`: PUT of a collection lifts every `auth.basic.password` out into it and writes the file blanked, GET puts them back, and DELETE drops the collection's keys.
A password still inline from before v1.5 is lifted on the first GET that sees it, so opening the app once cleans every collection and there is no migration to run.
`resolveFile()` accepts only the `group-`/`env-` prefixes and the `history` singleton, which is what stops the browser fetching `secrets.json` by name.
- `src/lib/` — `types.ts`, `utils.ts` (variable substitution + formatting), `storage.ts` (client API wrappers), `theme.tsx`.
- `src/components/` — `Sidebar`, `EnvironmentManager`, `RequestBuilder`, `KeyValueEditor`, `ResponseViewer`, `HistoryPanel`, `HistoryDetail`, `ConfirmDialog`.
`HistoryDetail` reuses `ResponseViewer` for the response pane, so a stored response formats exactly like a fresh one.
`resolveRequest(req, group, env)` takes the collection rather than a pre-computed auth, so the variables and the auth it applies always come from the same place.

## Development Notes

- **It runs as a background service, not a terminal you keep open.**
`~/Library/LaunchAgents/cz.matejalexander.local-postman.plist` keeps it on port 3010 across logins and restarts it if it dies; `~/.local/bin/postman` is the only command you need.
`postman` opens it (starting it first if it is down), and `start` / `stop` / `restart` / `status` / `logs` / `build` do what they say.
**`postman build` is the one to remember after changing the app**: the service runs `npm run start`, which serves the last build, so an edit is invisible until it is rebuilt.
Logs go to `~/Library/Logs/local-postman.log`.
The plist calls `postman serve` rather than node directly, because node comes from nvm and its path carries a version number that changes on the next `nvm install`; the script resolves it at run time instead.
- The application runs on port 3010 (`npm run dev` / `npm run start`).
A `npm run dev` cannot bind 3010 while the service holds it — `postman stop` first, or accept that dev picks another port.
- Both scripts set `NODE_OPTIONS=--use-system-ca`.
Node ships its own CA bundle and ignores the macOS keychain, so without this any host behind a private CA (an internal O2 endpoint, a corporate MITM proxy) fails the TLS handshake and the proxy reports it as a bare `fetch failed`.
- Runtime storage lives in `~/.local-postman`, overridable with `LOCAL_POSTMAN_DIR`.
It sits outside the repo on purpose: history records whatever headers were sent, credentials included, and a `.gitignore` entry protects git but not a zip, a backup, or `git clean -xdf`.
The repo's `storage/` is seed-only. `env-1.json` and `group-1.json` are committed, point at `https://jsonplaceholder.typicode.com`, and are copied into the storage dir when it has no JSON in it yet, so a fresh checkout can send a working request immediately.
- `APP_VERSION` is defined in `src/lib/types.ts` and shown in the header; keep it in sync with `package.json`.
- **Sharing a collection** means copying its `group-*.json` out of `~/.local-postman` by hand; there is no export UI.
Two things are not covered by the v1.5 split and still leak if you are careless:
`history.json` stores the resolved `Authorization` header of the last 50 sends, which is base64 of `user:pass`, so it is never shareable.
And a token pasted literally into a header value is written into the collection like any other string.
Put such a token in an **environment** variable and reference `{{token}}`: environments live in their own files, so copying a collection does not carry them.
