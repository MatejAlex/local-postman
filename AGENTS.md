## Features Implemented (v1.0)

1. **Collections of requests** — requests are organized into named groups; groups and requests can be added, renamed (double-click), and deleted.
Deleting a collection asks for confirmation first, naming it and how many requests go with it; deleting a single request does not.
Each collection has a ⚙ panel holding its **variables** and its **auth**, and the ⚙ turns accent-coloured once either is set.
2. **Collection variables** — `{{key}}` values scoped to one collection, set in its ⚙ panel and substituted into the URL, query params, headers and body at send time. A collection is the only place a variable can come from.
**There were environments until v1.7**, a second global set layered on top of these. They are gone: they did the same job twice, and having two sources for one `{{key}}` mostly produced confusion about which won. Anything an environment held belongs in the collection that uses it.
Two things about that older design are worth knowing, because both looked like broken substitution and neither was:
the sidebar list of environments was display-only until v1.6, so clicking one changed nothing;
and a `{{key}}` that is defined nowhere is left on the wire verbatim rather than blanked, which is deliberate but reads as a failure if you expected a value.
`requestVariables()` in `src/lib/utils.ts` is the single place a request's variables are assembled, and since v1.7 it has exactly one source to assemble them from.
3. **Collection colours (v1.7)** — each collection carries a colour, set in its ⚙ panel, shown as a dot beside its name and used to tint the header while one of its requests is open. Green for development, red for production; the meaning is yours, the palette is fixed.
4. **Reordering (v1.7)** — drag a collection by the ⠿ handle on its header row, or drag a request within its collection. A request cannot be dragged into a different collection.
Collections need an explicit `order` field because they are one file each and arrive in `readdir` order, which is neither insertion order nor stable between machines; a move rewrites every collection, since `order` is a position and moving one row shifts the rest.
Requests need no such field - they are an array inside one file, so their order is already the order they are stored in.
5. **Request builder** — method, URL with `{{variable}}` support, and tabs for query Params, Headers, and Body (None / JSON / Raw, with Beautify for JSON).
6. **Server proxy** — requests are forwarded through `/api/proxy` (server-side fetch) so arbitrary APIs work without browser CORS errors. Network and timeout failures return a structured error instead of crashing.
7. **Rich response viewer** — status, time, size, and tabs for Pretty / Raw / Headers, plus copy-to-clipboard.
**A failed request still shows its response.** The viewer only collapses to a bare message when nothing came back at all (`status === 0`: DNS, refused connection, timeout, or a request this app rejected before sending). Anything the server answered - a 401, a 500, an HTML error page - gets the failure banner *and* the full status bar, body and headers, because the server's own explanation is nearly always more specific than ours. It used to swallow all of it, so an MCP 401 read as a generic "Request failed" while the body sitting underneath named the exact credential that was rejected.
Pretty indents JSON, HTML and XML.
An HTML body also gets a **Preview** tab that renders it in a sandboxed iframe (no `allow-scripts`, no `allow-same-origin`), which is what makes an ORDS/APEX error page readable; it opens on that tab by default.
8. **Request history** — the last 50 sends are recorded in the History panel, each row showing the request's name, its status and two buttons: 🔍 opens the sent request and its response in a modal, ↻ sends it again.
History recorded before v1.2 has no name and shows "Unnamed request".
9. **File-based storage** — collections and history are persisted as JSON via `/api/storage` (one `group-*.json` per collection, plus `history.json`), in `~/.local-postman` rather than inside the repo. `env-*.json` files are no longer read; v1.7 leaves any it finds untouched.
10. **Theming** — three modes (Dark Grey default → Dark → Light) cycled via the header icon, persisted to localStorage.
11. **Shareable collections (v1.5)** — a `group-*.json` never contains a password, so it can be handed to a colleague as it sits.
Basic-auth passwords live in `~/.local-postman/secrets.json` instead, keyed by collection id or `collectionId/requestId`.
Nothing about using the app changes: the password box is typed into as before, and the storage route does the split on the way past.

12. **MCP requests (v1.6)** — a request has a **kind**, `http` or `mcp`, and an MCP one talks to an MCP server over Streamable HTTP.
It keeps the URL, the headers, the auth panel and `{{variable}}` substitution; it swaps Params and Body for a single **MCP** tab holding the method, the target and a JSON arguments box.
Seven methods: `tools/list`, `tools/call`, `prompts/list`, `prompts/get`, `resources/list`, `resources/read`, `ping`.
Add one from the collection header's **M** button.
**There is no connect step.** Every send runs the whole `initialize` → `notifications/initialized` → call → `DELETE` sequence and throws the session away, so a result never depends on what you clicked earlier. That costs a round-trip and buys statelessness; a full call against a local server lands in well under 200 ms.
Deliberately absent, and the reason this is not a fork of the reference inspector: no OAuth dance, no server-launching, no connection pane, no notifications/roots/sampling.

## Architecture

- `app/api/mcp/route.ts` — POST: the MCP client. One MCP call is three HTTP requests behind a session handshake, which is why it cannot be `/api/proxy` with a different body. It understands both response framings (plain JSON and SSE), unwraps the SSE one, and reports `application/json` either way so the viewer opens on Pretty. A JSON-RPC error becomes the response's `error` while the payload still fills the body; a tool that returns `isError` is a successful call and is left alone.
- `src/lib/mcp.ts` — the method catalogue, which methods need a target or take arguments, and `mcpParamsFor()`, which turns a config into JSON-RPC params **or** an error. Bad JSON is caught here so the message names the box the user is looking at, and such a request never reaches the network or the history.
- `app/api/proxy/route.ts` — POST: server-side request forwarder (kills CORS, 30s timeout).
- `app/api/storage/route.ts` — GET/PUT/DELETE: reads/writes `~/.local-postman/*.json` (path-traversal guarded), seeded from the repo's `storage/` on a first run. Only the `group-` prefix and the `history` singleton are accepted; `env-` was dropped with environments in v1.7.
It is also the only place that knows about `secrets.json`: PUT of a collection lifts every `auth.basic.password` out into it and writes the file blanked, GET puts them back, and DELETE drops the collection's keys.
A password still inline from before v1.5 is lifted on the first GET that sees it, so opening the app once cleans every collection and there is no migration to run.
`resolveFile()` accepts only the `group-` prefix and the `history` singleton, which is what stops the browser fetching `secrets.json` by name.
- `src/lib/` — `types.ts`, `utils.ts` (variable substitution + formatting), `storage.ts` (client API wrappers), `theme.tsx`, `useDragList.ts`.
`useDragList` carries the dragged index in `dataTransfer` rather than React state, because setting state on `dragstart` and reading it on `drop` loses a race and silently drops the move; and it types the payload per list, so a request dragged inside a collection does not also register on the collection list it bubbles through.
- `src/components/` — `Sidebar`, `RequestBuilder`, `KeyValueEditor`, `ResponseViewer`, `HistoryPanel`, `HistoryDetail`, `ConfirmDialog`.
`HistoryDetail` reuses `ResponseViewer` for the response pane, so a stored response formats exactly like a fresh one.
`resolveRequest(req, group)` takes the collection rather than a pre-computed auth, so the variables and the auth it applies always come from the same place.

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
The v1.5 split keeps Basic-auth **passwords** out of that file, and nothing else.
**A bearer token is not covered.** Whether it is pasted into a header or held as a collection variable, it is written into `group-*.json` like any other string, and since v1.7 removed environments there is no longer a place to put one that does not travel with the collection. Blank it before handing the file over.
`history.json` stores the resolved `Authorization` header of the last 50 sends, so it is never shareable regardless.
