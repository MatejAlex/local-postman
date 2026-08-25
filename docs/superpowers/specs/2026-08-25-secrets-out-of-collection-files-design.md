# local-postman v1.5 — Passwords out of collection files

Date: 2026-08-25

## Problem

A collection file is the natural unit to hand to someone else: it is one JSON file holding a
named set of requests against one API.
Today it cannot be handed to anyone, because the password is in it.

`RequestGroup.auth.basic.password` holds the collection-wide credential and every
`ApiRequest.auth.basic.password` holds a per-request one, and both are written verbatim into
`~/.local-postman/group-*.json`.
Sending that file to a colleague sends the password with it.

Sharing here means copying the file by hand.
There is no export step to scrub, so the file on disk has to be clean in the first place.

## Goals

1. A `group-*.json` never contains a password.
2. Nothing about using the app changes: the password box is typed into exactly as before.
3. Collections that already have passwords inline get cleaned without a manual migration step.
4. `types.ts`, `utils.ts` and every component keep their current shape and logic; the only edit
   outside the storage route is the version constant.

## Non-goals

Deliberately out of scope, and listed so the gaps are known rather than assumed closed:

- **Secret variables.**
  A collection or environment variable row still stores its value in the clear.
  A token pasted literally into a header is still shared with the file.
- **An export/import UI.**
  Sharing stays a manual file copy.
- **Keeping the plaintext out of the browser.**
  The client resolves the request and builds the `Authorization` header, so it necessarily holds
  the password in memory.
  This design moves where the value rests on disk, not who can see it at runtime.

## Design

### The secrets file

One new file, `~/.local-postman/secrets.json`, a flat map from owner id to password:

```json
{
  "group-1787560460827-olsur": "the collection-level password",
  "group-1787560460827-olsur/req-1787560481234-ab12x": "a per-request password"
}
```

A bare group id is that collection's own `auth.basic.password`.
A `groupId/requestId` pair is that request's.

JSON rather than a `.env`-style file: the app writes this, the keys are ids containing hyphens
and slashes, and a password may contain `=`, quotes, spaces or a newline.
JSON escapes all of that for free, and the storage layer already speaks nothing else.

`resolveFile()` in the storage route accepts only the `group-` and `env-` prefixes plus the
`history` singleton, so the name `secrets` is already rejected and the browser cannot fetch the
file through `/api/storage`.
This needs no new guard, only a test that keeps it true.

### Where the split happens

Entirely in `app/api/storage/route.ts`.
The client keeps sending and receiving whole `RequestGroup` objects with passwords in them, so no
other file changes.

**On PUT of a `group-*`:** walk the incoming group, lift `auth.basic.password` off the collection
and off each request into `secrets.json` under their keys, and write the group file with each of
those fields set to `''`.

**On GET:** read the group file, read `secrets.json`, and put the passwords back before
returning.
This applies to both the single-document form (`?name=group-X`) and the bulk form, which buckets
every file in the directory.

An empty password is stored as no entry at all rather than as an empty string, so clearing a
password removes the secret instead of leaving a blank one behind.

### Cleaning the collections that already exist

Handled inside the same GET, not as a separate migration.
When a group file still has a password inline and `secrets.json` has no entry for that key, the
route lifts the value out and rewrites the group file immediately.

Opening the app once therefore cleans every collection.
A GET that writes is impure, and the alternative is a script that has to be remembered before the
one time it matters, which is worse for a single-user localhost app whose whole point is that the
file on disk is safe to send.

The lift is skipped when an entry already exists, so `secrets.json` always wins and re-running is
harmless.

### Deleting

DELETE of `group-X` also drops every `secrets.json` key that is `group-X` or starts with
`group-X/`.
Without this the file accumulates the passwords of collections that no longer exist.

## Error handling

- **`secrets.json` missing or unparseable.**
  Treated as empty.
  A GET then returns collections with blank passwords rather than failing, and the next PUT
  rewrites the file.
  Losing the file loses passwords, which is the same exposure as losing any other file in
  `~/.local-postman`, and the collections themselves survive.
- **A concurrent write.**
  Read-modify-write on a shared file from one localhost user with one browser tab.
  Left as is; a lock would be machinery for a race that cannot realistically happen here.
- **A group file that is not a `RequestGroup`.**
  The walk reads through optional chaining and skips what it does not recognise, matching the
  existing route's habit of skipping an unreadable file rather than failing the whole read.

## Testing

There is no test setup in the repo today and this design does not add one.
Verification is manual, against the real storage directory:

1. Open a collection with a password, save any edit, and confirm `group-*.json` has
   `"password": ""` while `secrets.json` has the value.
2. Reload and confirm the password box is populated again and a request still authenticates.
3. Confirm a collection saved before v1.5 is cleaned by opening the app, without editing it.
4. Clear a password, save, and confirm the key is gone from `secrets.json`.
5. Delete a collection and confirm its keys are gone.
6. `GET /api/storage?name=secrets` returns a 400.

## What this does not fix

Recorded here so it is not mistaken for solved:

- **`history.json` records credentials.**
  Each entry stores the resolved `Authorization` header, which is base64 of `user:pass`.
  The file was deleted on 2026-08-25 and will refill as requests are sent.
  It is not covered by this design and must never be handed to anyone.
- **A collection with a token pasted into a header stays unshareable.**
  Header values are ordinary strings and are written into the file like any other.
  The fix needs no code: move the token into an *environment* variable and reference
  `{{token}}`, since environments live in their own files and copying a group file does not
  carry them.

## Version

`APP_VERSION` goes v1.4 to v1.5, in `src/lib/types.ts` and `package.json`.
