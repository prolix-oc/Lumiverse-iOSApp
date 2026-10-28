# Lumiverse iOS app

Native Swift/Rust client, widgets, Live Activities, notification extension, and
app build/verification tools. The app connects to a Lumiverse server; it does
not bundle the server. The `ios/` directory keeps the native project layout.

The connection screen has a collapsible **Connection history** list of the ten
most recent successful servers saved on this device. Select an address, then tap
**Connect**. **Remove** deletes an entry from history. While connected, hold two
fingers on the screen and choose **Connection history** in app controls to open
the list. VoiceOver and Switch Control users can use the **App controls** button.
The native wrapper cancels page touch handlers as soon as the second finger
lands and suppresses the page's context menu. Keep both fingers still for 650 ms
to open app controls. Single-finger actions and native scrolling/pinch zoom
remain available.

If a desktop theme makes the mobile interface unusable, hold two fingers still
for 650 ms to open app controls and choose **Disable custom theme**. This reloads
the current page with `safe-theme=1`, bypassing custom CSS and component CSS/TSX
overrides without deleting them or changing the theme on other devices. It works
with both the server frontend and the native cached interface. Use the recovered
interface to fix or disable the saved overrides. **Restore custom theme** removes
the recovery query and reloads the page; a server-wide safe theme flag still
applies. Recovery lasts for the loaded frontend session; reconnecting or a later
page load without the query uses the saved theme again.

On iOS 16 and later, **Resume last chat** and **Open favorites** are available
through Siri, Spotlight, and Shortcuts (including an assigned Action button).
They use the selected server and wait for sign-in/startup settings. Resume uses
the last chat opened on this device for that server/account; with no saved chat,
it opens Home. Navigation requests expire after ten minutes. These shortcuts
ship in ordinary builds and do not require push notifications or widgets.

The updated server frontend uses native iPhone haptics for long-press menus and
hold-to-queue. Completed exports offer **Share…**, plus **Preview** for formats
supported by Quick Look, while keeping the saved copy in Files.

Extension authorization and provider PKCE sign-in open in a native browser
window inside the app. Redirects retain the browser session, and the window
closes when authorization finishes. Use its Close button to cancel and return
to Lumiverse. This requires rebuilding the iOS app.

## Setup and build

Use Bun 1.4.2, Node.js, Rust/rustup, Xcode, and XcodeGen on macOS. Install Rust
targets `aarch64-apple-ios` and `aarch64-apple-ios-sim` with rustup.

```sh
bun install --frozen-lockfile
bun run build:ios-client --prepare-only --offline
bun run build:ios-client --simulator --debug
```

The prepare step creates/regenerates
`ios/tauri/src-tauri/gen/apple/lumiverse-ios-client.xcodeproj`. Open that project
in Xcode for native development. For a signed device build, select a development
team in Xcode or set `APPLE_DEVELOPMENT_TEAM`, then run `bun run build:ios-client`.
The ordinary build uses this project's pinned Tauri CLI and `assets/` icons.

Notifications, Live Activities, and character widgets are included in every build,
with their extensions and signing entitlements. Signed device builds require an
Apple Developer team provisioned for APNs and App Groups. The old
`--push-notifications` and `--widgets` flags are accepted but no longer needed.

For App Store Connect distribution, choose a new build number for each upload:

```sh
bun run build:ios-client --app-store-connect --build-number 11
```

Other options include `--unsigned` and `--native-cache-preview`. App Store Connect
distribution rejects experimental private WebKit APIs. Artifacts go to
`dist/ios/`; caches live in `.tmp/`. The release checker requires notifications,
Live Activities, and widgets without extra feature flags.

## Shared frontend inputs

Only native cache previews, frontend/audio integration checks, and the backend
notification encryption contract test need a separate `Lumiverse`
checkout. It defaults to the sibling folder; set `LUMIVERSE_BACKEND_DIR` to use
another absolute path. Install that checkout's root/frontend dependencies and
build its frontend before running integration checks. Its source and dependency
trees are never copied into this app project.

## Verify

```sh
bun run test
bun run test:release
bun run typecheck
bun run test:native --simulator SIMULATOR_UUID
bun run test:browser-windows --simulator SIMULATOR_UUID
```

Swift unit checks require macOS/Xcode. Device/simulator smoke tests are under
`scripts/smoke-test-ios-*.ts` and require an explicitly selected test device;
they can install test apps. `bun run build:sounds` regenerates the original
notification tones.

## Local state and source control

The extraction preserves generated Xcode projects, local build artifacts, and
platform caches in ignored directories. Run the prepare command after moving
the project to refresh generated paths. Signing remains in the macOS Keychain
and Xcode provisioning profiles. Do not commit local signing or account files.
`LICENSE.md` is retained from the original project.

## Continuous integration

`.github/workflows/ci.yml` runs independent unit/type checks on every push and
pull request. A separate integration job checks out the exact backend commit in
`backend-source.json` into `backend/`, sets `LUMIVERSE_BACKEND_DIR`, verifies the
checkout revision, and runs `test:backend`. No sibling checkout is needed for
`bun run test` / `bun run test:unit`.

`bun run test:ci` runs all local CI checks, including backend integration. That
command requires the backend checkout. Update the full SHA in
`backend-source.json` intentionally when adopting a newer backend contract;
missing checkouts and revision mismatches fail the integration job. CI does not
skip tests when required shared source is missing. Only the integration job
needs backend dependencies; native app builds and device smoke tests remain
separate from these source-level CI checks.
