# Local Postman, native (v2.0 prototype)

The SwiftUI rewrite of the web app in the repo root. It reads and writes the same `~/.local-postman` files in the same format, so the two can run side by side while this one replaces the other.

## Run it

You need **macOS 26 and Xcode 26** (Liquid Glass needs the macOS 26 SDK).

**From Xcode, while developing:**

```bash
open macos/Package.swift
```

Pick the **LocalPostman** scheme and press ⌘R.

**As a real app in /Applications:**

```bash
macos/scripts/build-app.sh --install
```

This builds a release binary, wraps it in `Local Postman.app` (with an Info.plist that allows plain-http and LAN hosts), signs it ad hoc, and opens it.
Re-run the script after each change; there is no background service to restart.

**Core tests** (these also run on Linux):

```bash
cd macos && swift test
```

## Layout

| Path | What |
|---|---|
| `Sources/PostmanCore/` | Everything that is not a view: models, `{{variable}}` substitution, request resolution, the HTTP sender, the MCP client, storage with the `secrets.json` split, and the JSON/HTML/XML formatters. No UI imports. |
| `Sources/LocalPostman/` | The SwiftUI app. `AppModel` holds all state and does all saving; the views only read it and call into it. |
| `Tests/PostmanCoreTests/` | 50 tests covering the behaviour carried over from the web app. |
| `scripts/build-app.sh` | Builds and installs the `.app`. |

## What changed from the web app

Everything the web app did is here (collections, variables, colours, reordering, HTTP and MCP requests, Basic auth with the password split, the response viewer with an HTML preview, and history with inspect and replay).
These are the differences:

- **No proxy.** A native app has no CORS problem, so requests go straight out through `URLSession`. The proxy's other jobs are still done: a 30 s timeout, redirects followed by hand with credentials dropped when the origin changes, and errors returned as a response instead of a crash.
- **System certificates just work.** `URLSession` trusts the macOS keychain, so hosts behind a private CA no longer need `--use-system-ca`.
- **No background service.** No Node, no nvm, no LaunchAgent and no `postman build`. It's an app.
- **The response pane can be resized and maximised.** Drag the divider (double-click it to reset); ⇧⌘↩ gives the response the whole pane; ⌘\\ switches between stacked and side-by-side.
- **Each request keeps its last response** for the session, so switching requests no longer throws it away, and the app reopens on the request you left.
- **A request in flight can be cancelled** (⌘. or the Cancel button).
- **Large bodies stay fast.** Bodies are shown in a native text view with JSON/HTML syntax colours and ⌘F find. Formatting runs off the main thread and keeps keys in the server's order.
- **Appearance follows macOS** (or is forced to Light or Dark under View ▸ Appearance). The web app's three themes are gone.
- **The URL bar shows what will actually be sent** under it, and warns about any `{{variable}}` that isn't defined.
- **History can be filtered**, and a replay opens its result.
- **The JSON body editor warns about invalid JSON** before you send it.

## Keyboard

| Keys | Action |
|---|---|
| ⌘↩ | Send |
| ⌘. | Cancel the request in flight |
| ⌘N / ⌥⌘N | New request / new MCP request in the current collection |
| ⇧⌘N | New collection |
| ⌘D | Duplicate the request |
| ⌘L | Focus the URL |
| ⌥⌘, | Collection settings |
| ⌘Y | Show/hide history |
| ⇧⌘↩ | Maximise/restore the response |
| ⌘\\ | Stacked / side-by-side layout |
| ⇧⌘R | Reload from disk (after editing files by hand, or using the web app) |
| ⌘F | Find in a body |

## Known gaps in the prototype

- **⌘\\ needs a US-style backslash.** On a Czech layout use the toolbar's layout button instead.
- **A multi-megabyte body is still not free to edit.** Typing into a 2 MB body costs about 20 ms a keystroke; an ordinary body costs nothing measurable.
- No app icon.
- If the web app and this app are both open, the last one to save a collection wins. Use ⇧⌘R to pick up changes made by the other.
- Passwords are still kept in `secrets.json`. They move to the Keychain once the web app is retired, so the web app keeps working until then.
