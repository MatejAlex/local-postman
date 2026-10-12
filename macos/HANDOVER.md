# Handover: finish the native app on a Mac

You are picking up the SwiftUI rewrite of local-postman on the Mac it will run on.
It was written in a Linux cloud session that could compile and test the core but could never build or look at the UI.
Your job is to get it building, see it, and fix what is broken. **Do not redesign anything.** The owner will give design feedback after using it.

Branch: `claude/swift-app-mcp-server-j4o9je`. Commit in small steps and push to that same branch. Do not open a PR unless asked.

## Read first
- `macos/README.md` covers running it, the layout, what changed from the web app, and the keyboard shortcuts.
- The "Native app" section of `AGENTS.md`.
- The web app (`app/`, `src/`) is the behavioural reference. `macos/Sources/PostmanCore` is a port of `src/lib` plus the three API routes.

## State
| Part | Status |
|---|---|
| `Sources/PostmanCore` | Compiles. 44 tests pass on Linux (Swift 6.1). This is the ground truth: keep `swift test` green, and put any behaviour change here with a test. |
| `Sources/LocalPostman` (SwiftUI) | **Never compiled.** It passed a syntax parse and one review pass for compile errors, which found none for certain. Expect some anyway. |
| `scripts/build-app.sh` | Untested. It builds a release binary, wraps it in `dist/Local Postman.app` with an Info.plist (ATS allows http and LAN), signs it ad hoc, and `--install` copies it to /Applications. |

Requirements are macOS 26 and Xcode 26. The package sets `platforms: [.macOS("26.0")]`, and the app target uses `.swiftLanguageMode(.v5)` on purpose to keep concurrency diagnostics quiet.

## Step 1: make it build
```bash
cd macos
swift test          # expect 44 passing
swift build         # the app target compiles here for the first time
```
Fix compile errors with minimal, local changes in the style of the surrounding code.
If a Liquid Glass API turns out to have a different signature (`.glassEffect(_:in:)`, `Glass.regular.tint(_:)`, `.buttonStyle(.glass)` / `.glassProminent`), use the real one. Don't drop the effect.

## Step 2: run it and look
`swift run LocalPostman` or `scripts/build-app.sh --install`. Take screenshots with `screencapture -x <file>` (or `-l <windowid>`) and look at them yourself before claiming anything works.

**Back up the owner's data first.** The app reads and writes the same files as the web app:
`cp -R ~/.local-postman ~/.local-postman.backup-$(date +%s)`.
Alternatively, point it at a scratch directory with `LOCAL_POSTMAN_DIR=/tmp/lp-test swift run LocalPostman`. That dir gets seeded with the jsonplaceholder sample collection.

Walk through:
- The sidebar: collections with colour dots, request rows with coloured method badges, hover buttons (+, M, gear), double-click rename, right-click menus, the delete-collection confirmation.
- The request editor: name, the glass URL bar tinted with the collection's colour, the resolved-URL line under it, and the Params / Auth / Headers / Body tabs. An MCP request has MCP / Auth / Headers instead.
- Send "List users" from the seed collection. It should come back 200 with pretty JSON in server key order, syntax-coloured, with ⌘F find working.
- The response pane, in three layouts: stacked, side by side (⌘\\), and maximised (⇧⌘↩). Check that the divider drags.
- An HTML response: the Preview tab opens by default, and links in it must not navigate. Any page returning HTML will do.
- History (⌘Y): the filter, double-click opening the detail sheet, the request pane of that sheet, and Send Again updating the sheet in place.
- The collection settings sheet: name, colour, variables, auth, with Save and Cancel.
- Appearance: View ▸ Appearance in Light and in Dark. Check that it stays readable in both.

## Known suspects (check these specifically)
1. **Dragging to reorder collections.** `.onMove` sits on a `ForEach` of `DisclosureGroup`s in `SidebarView.swift` and may do nothing on macOS. The right-click Move Up/Down items are the fallback. If drag fails, find a way that works; don't just remove it. Dragging a request within a collection should work and must never move it into another collection.
2. **The method picker colour.** It's a `Menu` with `.menuStyle(.borderlessButton)`, and the colour may be ignored. The style is deprecated, so a warning is expected.
3. **`HTMLPreview.Coordinator.decidePolicyFor`** may not match the SDK signature exactly. If it doesn't, link blocking silently stops working. Look for a "nearly matches" warning.
4. **`AppModel.binding(forRequest:)`** uses `Binding(get:set:)` closures that touch main-actor state. That should be fine, but it is the most likely concurrency complaint.
5. **Typing performance.** Every keystroke in the editor writes into `AppModel.groups`, which re-renders the sidebar. If typing lags, scope the observation down. Saving is already debounced to 400 ms.

## Behaviour that must not change
These are carried over deliberately from the web app; see `AGENTS.md` for the reasons.
- A `{{key}}` defined nowhere is sent verbatim, not blanked.
- A failed request that got an answer still shows the full response. Only `status == 0` collapses to a bare message.
- Every MCP send runs the full initialize → initialized → call → DELETE sequence, with no connect step.
- `group-*.json` never contains a Basic-auth password; those go to `secrets.json`. Keep the file formats compatible with the web app.
- Credentials are dropped when a redirect changes origin.

## When you are done
- `swift test` passes, `swift build` has no errors, and the app runs.
- Everything is pushed to the branch.
- You can give the owner a short list of what you fixed, what you saw in the screenshots, and anything you could not resolve.
