# local-postman

A local-first API client — a lightweight Postman that also speaks MCP.
It runs on your machine, stores everything as plain JSON files you own, and sends requests through a server-side proxy so CORS never gets in the way.

`AGENTS.md` is the full feature and architecture breakdown; this file is enough to clone it and run it.

## Getting started

```bash
npm install
npm run dev          # http://localhost:3010
```

For a long-lived instance, build once and serve the build:

```bash
npm run build
npm run start        # same port, no file watching
```

Both scripts set `NODE_OPTIONS=--use-system-ca`.
Node ships its own CA bundle and ignores the system keychain, so without it any host behind a private CA or a corporate proxy fails the TLS handshake and the error surfaces as a bare `fetch failed`.

## Where your data lives

**Nothing is written inside the repo.**
Everything goes to `~/.local-postman/`, overridable with the `LOCAL_POSTMAN_DIR` environment variable.
That is deliberate: request history records whatever headers were sent, credentials included, and a `.gitignore` entry protects git but not a zip, a backup, or `git clean -xdf`.

The directory is created on the **first API call**, not at boot, and files appear as you need them:

| File | Created when | Holds |
|---|---|---|
| `group-*.json` | first load | one collection each — its requests, variables, colour and order |
| `history.json` | first send | the last 50 sends, each replayable |
| `secrets.json` | first save of a collection with a Basic-auth password | those passwords, keyed by collection or `collection/request` |

On a genuinely first run the directory is empty, so the repo's `storage/` is copied in as a seed: one demo collection pointing at `jsonplaceholder.typicode.com`, enough to send a working request immediately.
Seeding only happens when the directory contains no `.json` at all, so it never overwrites your work.

### Credentials

Basic-auth **passwords** are lifted out of the collection file on save and kept in `secrets.json`, then put back when the app loads.
A `group-*.json` therefore never contains one, and can be handed to a colleague as it sits.

**Bearer tokens are not covered by that split.**
Whether typed into a header or held as a collection variable, a token is written into `group-*.json` like any other string.
Blank it before sharing the file.
`history.json` records resolved `Authorization` headers and is never shareable.

## What it does

1. **Collections** of requests, added, renamed by double-click, reordered by drag, and deleted.
Each has a ⚙ panel holding its variables, its auth and its colour.
2. **Collection variables** — `{{key}}` values substituted into the URL, query params, headers and body at send time.
This is how a base URL works: set `base` on the collection and write `{{base}}/principal`, so pointing thirteen requests at production is one edit.
A `{{key}}` that is defined nowhere is left on the wire verbatim rather than blanked, so a typo shows up in the response instead of silently changing the URL.
3. **Colours and ordering** — a collection's colour tags it in the sidebar and tints the header while one of its requests is open.
Drag collections by the ⠿ handle, and requests within their collection.
4. **Request builder** — method, URL, and tabs for Params, Auth, Headers and Body (None / JSON / Raw, with Beautify).
5. **MCP requests** — talk to an MCP server over Streamable HTTP.
A request has a kind, `http` or `mcp`; an MCP one keeps the URL, headers, auth and variables and swaps Params/Body for one MCP tab holding the method, its target and a JSON arguments box.
Seven methods: `tools/list`, `tools/call`, `prompts/list`, `prompts/get`, `resources/list`, `resources/read`, `ping`.
There is no connect step — every send runs the whole `initialize` → notify → call → close sequence, so a result never depends on what you clicked before it.
Add one with the **M** button on a collection.
6. **Server proxy** — requests go out from the server (`/api/proxy`), so any API works without CORS errors.
Redirects are followed by hand and credentials dropped on a cross-origin hop.
7. **Response viewer** — status, time and size, with Pretty / Raw / Headers tabs, and a sandboxed Preview for HTML so an ORDS or APEX error page is readable.
8. **History** — the last 50 sends, each inspectable and re-runnable.
9. **Theming** — Dark Grey, Dark and Light, cycled from the header.

## Security model

The proxy is a local developer tool, so reaching `localhost` and internal dev servers is a feature rather than a bug and private addresses are **not** blocked.
The real risk is a third-party page POSTing to the proxy to use your machine as one, so both `/api/proxy` and `/api/mcp` require the request to originate from this app's own UI, and the storage route accepts only the `group-` prefix and the `history` singleton — which is what stops a browser fetching `secrets.json` by name.

Do not expose this app to a network you do not control.
