# Lumiverse iOS app

Native Swift/Rust client, widgets, Live Activities, notification extension, and
app build/verification tools. The app connects to a Lumiverse server; it does
not bundle the server. The `ios/` directory keeps the native project layout.

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

Existing options remain available: `--unsigned`, `--push-notifications`,
`--widgets`, `--native-cache-preview`, `--app-store-connect`, and `--build-number`.
App Store Connect distribution requires a build number and rejects experimental
private WebKit APIs. Artifacts go to `dist/ios/`; caches live in `.tmp/`.

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
