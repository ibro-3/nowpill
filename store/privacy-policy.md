# NowPill Privacy Policy

_Last updated: 2026-11-26_

NowPill is a local-first habit tracker and to-do list. This policy explains what
data the app handles and where it lives. The short version: **your data stays on
your devices. We do not collect, transmit, or sell anything.**

## What data NowPill stores

Everything you create in the app is stored locally on your device:

- Habits, check-ins, streak history, and freeze tokens
- Tasks, subtasks, tags, priorities, and due dates
- Personal chat notes you write to yourself
- App preferences (theme, motion, language, reminder defaults, sync settings)

This data lives in a SQLite database in the app's private storage
(`app.nowpill` on Android). It never leaves your device unless **you** move it
using one of the features below.

## Features that move your data (all user-initiated)

- **Export / Import** — you can export everything to a JSON file and import it
  elsewhere. The file goes wherever you choose to save or share it.
- **Automatic backups** — NowPill keeps up to 7 daily snapshots in the app's
  documents folder on the same device. Restoring is always an explicit action
  you confirm. These files are local; nothing is uploaded.
- **Folder sync (optional, off by default)** — if you enable sync, NowPill reads
  and writes small JSON files in a folder **you choose**. NowPill does not copy
  those files anywhere itself; a transport you already use (Syncthing, Dropbox,
  iCloud Drive, a shared drive, …) moves them between your devices. NowPill has
  no server, no account system, and no knowledge of where the folder is hosted.
  The files contain only your habit/task/note data and a random per-device id.
- **Update checks (configurable, default on launch)** — NowPill can contact
  GitHub's public API (`api.github.com`) to check for a newer release and, if
  you tap Download, fetch the release asset from GitHub. No personal data is
  uploaded; GitHub necessarily sees your device's IP address. You can turn
  checks off or limit them to manual checks in Settings → Updates. Downloads are
  verified against the release's SHA-256 checksum before installation.

## What NowPill does NOT do

- No account, sign-in, or registration
- No analytics, telemetry, or crash reporting sent anywhere
- No advertising or advertising identifiers
- No third-party SDKs that collect data
- No NowPill server and no analytics/telemetry endpoints. The only outbound
  requests are the optional GitHub update checks and downloads described above.

## Permissions

- **Notifications** — to show the reminders you schedule.
- **Exact alarms (Android)** — so reminders fire on time; optional, with a
  graceful fallback when not granted.
- **Storage access (Android, only if you enable folder sync)** — access is
  limited to the single folder you pick through the system file picker
  (Storage Access Framework). NowPill cannot read anything else.

## Children

NowPill collects no data from anyone, including children.

## Changes

If this policy changes, the updated version ships with the app and is published
at the same location. Material changes will be noted in the changelog.

## Contact

Questions? Open an issue at the project repository:
https://github.com/ibro-3/nowpill

---

# Google Play — Data safety form copy

Use these answers when completing the Play Console Data safety section.

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | N/A — no data is transmitted by the app |
| Do you provide a way for users to request that their data be deleted? | Yes — all data is local; users delete it in-app (archive/delete) or by uninstalling. Export/import gives full ownership. |

Data types (all answered **Not collected** / **Not shared**):

- Location: not collected
- Personal info (name, email, user ids, address, phone, race/ethnicity,
  political/religious beliefs, sexual orientation, other): not collected
- Financial info: not collected
- Health and fitness: **not collected** — habit/check-in data is stored only
  on-device and is never transmitted to the developer or any third party
- Messages: not collected
- Photos and videos: not collected
- Audio files: not collected
- Files and docs: not collected by the developer — the optional folder-sync
  feature reads/writes files in a user-chosen folder locally; the app itself
  does not upload or share them
- Calendar: not collected
- Contacts: not collected
- App activity (app interactions, in-app search history, installed apps,
  other user-generated content, other actions): not collected
- Web browsing: not collected
- App info and performance (crash logs, diagnostics, other app performance
  data): not collected
- Device or other ids: not collected

**Note on the random device id used by folder sync:** it is generated locally,
stored locally, and written only into the sync files inside the user's own
chosen folder. It is not transmitted to the developer or any third party by the
app, and is not used for tracking, analytics, or advertising. It is therefore
not a "collected" device id under Play's definition (collection = transmitting
off-device to the developer or a third party).

## Security practices

- Data isn't encrypted in transit because the app transmits no data. Local
  database storage uses the platform's app-private sandbox.
- Users can request data deletion by deleting items in-app or uninstalling;
  no server-side copy exists.

## Privacy policy URL

Host this file (or a rendered copy) at a public URL for the Play listing, e.g.
`https://github.com/ibro-3/nowpill/blob/main/store/privacy-policy.md`.
