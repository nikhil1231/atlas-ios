# Atlas for iOS

A native SwiftUI, iPhone-first client for the hosted Atlas backend. Requires **iOS 17+** and
Xcode 15+ with a suitable iOS SDK. No third-party iOS dependencies or local backend are needed.

- Interruptible Realtime voice conversations, with echo cancellation and native audio routing.
- Server-owned tools route the full corrected request into Atlas's existing capture pipeline.
  Work runs asynchronously; the conversation stays open and reports actual completion results.
- Persistent unanswered questions, answered by voice, and cancellable deferred operations.
- Lock Screen / Dynamic Island Live Activities for questions and pending work, updated through APNs.
- Notification inbox with read receipts, full notification details, and links to tracked requests.
- Hosted-only HTTPS/WSS networking; bearer and optional Cloudflare service credentials in Keychain.

## What's in it

- **Today**: Atlas's questions and held shopping changes (tap an option, type an answer, send now or
  cancel), quick add, Focus, overdue, your day (calendar, reminders, Ocado/HelloFresh deliveries),
  your list, yesterday's leftovers (carry over or let go) and a peek at tomorrow.
- **Everything**: to-dos by area with a Someday shelf, people by who's overdue for contact (one tap
  logs it), projects with their boards, goals, habits, inbox suggestions and project refiles, and
  recent captures with undo. Search covers titles and notes.
- **Item sheet**: rename, describe, pin, must-do, plan for today/tomorrow, deadline, reminder time,
  area, kind, snooze (or wake), notes, contact and cadence, done/reopen, drop, delete. A long press on
  any row has the quick ones.
- **Widgets**: Today (small/medium/large and Lock Screen) and Focus, with tick buttons that work
  without opening the app; an iOS 18 control (Control Center, Lock Screen, Action Button) to talk.
- **Siri and Shortcuts**: "Tell Atlas …" files a thought and says what happened; "What's on today in
  Atlas" reads out the day; "Talk to Atlas" opens voice.
- **Share sheet**: send a link or text (plus a note) to Atlas from any app.
- **Apple Reminders sync** (Settings → Reminders): EventKit does what the Atlas Sync Shortcut did,
  both ways, on open, whenever Reminders changes, straight after a capture and in the background.
- Voice, text capture, Activity, the notification inbox and Live Activities, as before.

Direct changes go through `POST /api/mobile/operations` and live updates through
`GET /api/mobile/events`; both need the matching Atlas backend (`ios-integration` branch in
`../atlas`). Edits show as pending until Atlas confirms them, a failure says so, and a retry of the
same change can't apply it twice.

## Open and run on a Mac

1. Open `Atlas.xcodeproj`. The project and shared **Atlas** scheme are checked in.
2. Select your Apple developer team for **Atlas**, **AtlasWidgets**, **AtlasShare** and **AtlasTests**.
   If the default bundle IDs are unavailable, change `ing.nikhil.noodle` and
   `ing.nikhil.noodle.activity` together; the extension's ID must be prefixed by the app ID.
3. Ensure the main app's App ID has the **Push Notifications** capability. Xcode's project
   declares it and uses `Config/Atlas.entitlements`. The widget extension embeds in the app.
   Live Activities use ActivityKit and `NSSupportsLiveActivities`. The app and both extensions share
   the App Group `group.ing.nikhil.noodle` (the widget snapshot) and the keychain group
   `ing.nikhil.noodle.shared` (credentials, so widgets, Siri and the share sheet can reach Atlas). Both
   are in the `.entitlements` files and `ATLAS_APP_GROUP`/`ATLAS_KEYCHAIN_GROUP` in the xcconfigs;
   automatic signing registers them. The share extension's bundle ID is `ing.nikhil.noodle.share`.
4. Confirm `ATLAS_BACKEND_HOST` in `Config/Debug.xcconfig` and `Config/Release.xcconfig`.
   It defaults to `atlas.nikhil.ing`. The app rejects HTTP, localhost, and numeric IP hosts.
5. Build/run the **Atlas** scheme on your iPhone. Open the sliders button to
   enter the existing Atlas bearer token and both Cloudflare service-token fields. No OpenAI
   or Apple private key belongs in the app.
6. In Settings, enable notifications. Allow the microphone when you first start a conversation.

Debug builds register APNs **sandbox** tokens; Release/TestFlight builds register **production**
tokens. If you sign a custom configuration, keep `APNS_ENVIRONMENT` and
`ATLAS_PUSH_ENVIRONMENT` consistent with its provisioning profile.

The backend adapter in the sibling Atlas project must be deployed first. See
[`../atlas/docs/ios-client.md`](../atlas/docs/ios-client.md) for its environment, architecture,
endpoints, and constraints. At minimum, the server needs `OPENAI_API_KEY` in addition to its
existing capture configuration. Push delivery also needs an APNs key, key ID, team ID, and bundle ID.
Existing OpenRouter credentials still power Atlas's capture classifier/answerer.

## Build and tests

```sh
xcodebuild -project Atlas.xcodeproj -scheme Atlas \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Pick an installed iPhone simulator from `xcrun simctl list devices available`:
xcodebuild test -project Atlas.xcodeproj -scheme Atlas \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

`AtlasTests` checks backend JSON and legacy compatibility, ActivityKit payloads, event framing,
authenticated AsyncBytes transport, replay/deduplication, cursor expiry, snapshot races, cache
isolation, reconnect backoff, foreground cancellation, notification policy and voice render timings.
Build and simulator tests have been run on the Mac with Xcode 26.4.1 and iOS 18.4.
`.github/workflows/ios.yml` runs the shared scheme when hosted on GitHub.

The app builds and its contract tests run in the iOS simulator. Microphone quality,
Bluetooth routing, signed-device startup time, and hosted voice behavior still require an iPhone.
The checked-in project can be regenerated after adding/removing files:

```sh
python3 scripts/generate_project.py
```

The generator uses only Python's standard library. Edit bundle IDs/build settings in its source
if you want those changes to survive regeneration; ordinary signing choices can be set in Xcode.

## Device acceptance checks

1. Use a mixed request: “Remind me to call Mum tomorrow morning, and what’s on my calendar this
   weekend?” Verify the original pipeline processes both clauses and the spoken result matches it.
2. Interrupt Atlas while it speaks; playback should stop and unplayed audio should be truncated
   from the model's context. Test both built-in speaker and Bluetooth.
3. Ask something ambiguous that needs a question. Verify it appears in Activity and on the Lock
   Screen. End the conversation, reopen the app, select the question, and answer by voice. The
   question should close only after the backend successfully processes the answer.
4. Ask to perform an operation in three minutes. Verify its queued status/countdown, then cancel
   it in Activity before it starts. Verify no corresponding capture was executed.
5. Submit work, then lock the phone. Verify the server finishes it, sends an alert, and updates or
   ends an existing Live Activity. Tap an alert to see its full request/result, and check read state.
6. Disconnect the network during voice. Verify the conversation ends with an error and previously
   submitted requests remain in Activity after reconnecting. Never automatically retry a failed
   operation that may have caused effects.
7. Deny microphone/notification permissions, reject a Cloudflare token, and restart the backend
   during a capture. Check that each outcome is visible without claiming success.

## MVP boundaries

The app uses Atlas's existing text/voice capture pipeline and preserves its correction,
clarification, cancellation and cutoff rules. The Today and Everything screens use the shared reads and typed-operation APIs. They don't
add a separate shopping editor; the server owns shopping execution and background read corrections.
The inbox shows the newest 200 notifications and retains all active operations.

Live Activities start in the foreground (up to three). APNs updates existing activities while
suspended; starting a brand-new activity remotely is not implemented. A new background question
uses an alert until you open the app. Voice runs in the foreground and ends when you leave the app;
pending work continues server-side. Device reminders sync through EventKit when enabled in Settings, or through the existing Shortcut.

The queue assumes the existing **single uvicorn worker / single replica** deployment. Running
requests interrupted by a restart are marked uncertain and never automatically repeated. An
idempotency UUID prevents duplicate HTTP submissions; it does not make external side effects atomic.

Release polish such as an app icon, distribution screenshots, a public privacy-policy URL,
and TestFlight submission is outside this implementation. The privacy manifest declares microphone
content, submitted content, device identifiers, and app-local UserDefaults access; review it against
any backend data-handling changes before distribution.

## Voice and text updates

The Talk screen includes a text composer using `POST /api/mobile/requests`; no microphone or
Realtime session is needed. The latest request links to its status and result. A manual retry of
an unchanged message reuses its submission UUID, so an uncertain network response does not create
a second operation. Drafts and this retry identity last only for the current app process.

Voice readiness and playback are coordinated with the backend using `client_playback=1`,
`noodle.audio_ready`, and `noodle.playback`. Deploy the matching changes in the sibling `../atlas`
repository for the opening greeting, natural speech instructions, and delayed completion updates.
The previous backend remains compatible with the client but ignores these new coordination events.
Keychain loading happens off the main thread, and the audio engine is created only when needed.

## Responsiveness and offline state

- Latest state and the journal cursor are written together, atomically, in Application Support.
  The cache is excluded from backup and protected until first unlock. A SHA-256 scope includes
  the backend URL and all account credentials; credentials themselves remain in Keychain.
  Changing credentials clears cached state and ends the previous account's Live Activities.
- Saved state renders as soon as Keychain is available, before waiting for HTTP. Its age stays
  visible until fresh data arrives. Offline failures retain the last successful state.
- Foreground updates use authenticated `GET /api/mobile/events?after=...`. Replayed events are
  deduplicated by sequence. Expired cursors and server reset frames fetch a new snapshot.
  State snapshots cannot rewind newer events or voice acceptance received during the fetch.
- Streaming reconnects after 5, 10, 20, then at most 30 seconds. While unavailable, state is
  checked every five seconds. Older servers without a cursor continue to use five-second
  polling. A healthy stream has no periodic state polling. Server heartbeats detect stalls;
  leaving the foreground cancels streaming, polling and voice.
- Operation updates reach Activity and Live Activities directly. `notification.created` currently
  contains only an ID, so those events and terminal/question operations trigger a coalesced
  snapshot for the inbox. Until it arrives, the durable cursor stays behind the missing record;
  restart/replay therefore cannot silently lose an inbox notification.
- Scheduled work is labelled as awaiting execution. Partial success is shown separately from
  completion. Accepted work remains in local state when voice disconnects; no action is
  automatically replayed. The legacy text endpoint and APNs content-state fields remain supported.
- Foreground banners/sounds are suppressed only for a request whose update has started rendering
  in this voice session, or a duplicate notification ID. Alerts remain in the notification list
  and inbox. Unrelated requests keep their normal alerts; arrival before playback keeps its alert.

## Device timing diagnostics

In Console or Xcode, filter subsystem `ing.nikhil.noodle`, category `responsiveness`. Samples include
random session/turn IDs, metric names and milliseconds, with no transcript, audio, basket content
or credentials. The in-process sample ring retains 200 values. Nothing is uploaded automatically.

`speech_stop_received_to_first_render` measures the server speech-stop event's receipt to the
first render timestamp. `speech_stop_received_to_estimated_audible` adds the audio engine output
presentation latency. `local_speech_end_to_estimated_audible` uses a local PCM energy estimate;
it does not control the conversation's server VAD. The first response per turn can be an
acknowledgement or a full answer. These are estimates, not measured acoustic speaker output.
Hardware routing, background APNs delivery, live hosted voice, and real p95 timings still need
signed-iPhone acceptance checks; simulator tests don't establish those results.

## Platform views

The app opens on **Today**, alongside **Everything**, **Talk**, **Activity**, and **Inbox**.
Today uses the server's logical day and preserves its late-night cutoff, overdue group,
planned tasks, timed reminders, completed tasks, and yesterday's leftovers. Google Calendar
appointments come from the authenticated calendar read; local events remain available if
Calendar is disconnected. Focus shows pinned and important active items.

Everything reads all items, including project tasks and completed work. Search within to-dos,
projects, goals, habits, people, or the capture inbox; filter by life area and switch to completed
items. Open a project to browse its active tasks. Item details support renaming, planning for
today or tomorrow, and completing to-dos. Capture through Talk creates new items through
Atlas's existing classifier.

Reads use `POST /api/mobile/reads` with device timezone. They refresh every 15 seconds while
foregrounded and on pull to refresh. Each source retains its last successful in-memory result
on failure and discloses unavailable/stale data; these new read snapshots are not persisted
between launches. The existing Activity/notification disk cache is unchanged.
Changes use `items.update` through `POST /api/mobile/operations`: rows stay pending until
tracked work finishes, errors remain visible, and uncertain retries reuse the submission UUID
for that action during the current process. Changes are never automatically resubmitted.
These reads and operations need the backend from the `ios-integration` branch deployed.

The design follows the website's paper, ink, ochre, and hairline-divider palette, with native
serif headings. Light and dark appearances follow the device setting. Platform tests cover
realistic read envelopes, offline retention, account clearing, mutation retry identity, pending
completion, and light/dark screen rendering. Live hosted authentication, calendar availability,
and signed-device acceptance still require the configured account.

## Naming and upgrades

The app is Atlas everywhere you see it, but some identifiers keep their Noodle-era values so an
installed app upgrades in place: the bundle IDs (`ing.nikhil.noodle…`, which the backend's APNs
topic expects), the keychain item, the offline cache folder, the `noodle://` link scheme (alongside
`atlas://`), and the `noodle.*` voice events the backend sends. Saved credentials move into the
shared keychain group on first launch and become readable after first unlock, so widgets and
background refresh work while the phone is locked. The default host is now `atlas.nikhil.ing`;
changing host clears the offline cache once, since its scope includes the backend URL.
