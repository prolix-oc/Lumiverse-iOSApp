#!/usr/bin/env bun
import { mkdirSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

const root = resolve(import.meta.dir, '..')
const simulator = process.argv[process.argv.indexOf('--simulator') + 1]
if (!process.argv.includes('--simulator') || !simulator || simulator.startsWith('--'))
  throw new Error('Specify an iOS simulator UUID with --simulator.')
const directory = resolve(root, '.tmp/ios-browser-windows')
mkdirSync(directory, { recursive: true })
writeFileSync(resolve(directory, 'project.yml'), JSON.stringify({
  name: 'LumiverseBrowserWindows',
  options: { deploymentTarget: { iOS: '17.0' } },
  settings: { base: { SWIFT_VERSION: '5.0', GENERATE_INFOPLIST_FILE: true,
    CODE_SIGNING_ALLOWED: 'YES', CODE_SIGN_IDENTITY: '-', CODE_SIGNING_REQUIRED: 'NO' } },
  targets: {
    BrowserWindowHost: {
      type: 'application', platform: 'iOS', sources: [resolve(root, 'ios/browser-window-tests/Host')],
      info: { path: 'Host.plist', properties: { NSAppTransportSecurity: { NSAllowsArbitraryLoads: true } } },
      settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: 'chat.lumiverse.browser-window-host' } },
    },
    BrowserWindowTests: {
      type: 'bundle.unit-test', platform: 'iOS',
      sources: [{ path: resolve(root, 'ios/browser-window-tests'), excludes: ['Host'] },
        ...['NativeBrowserWindows', 'NativeServerOrigin'].map(file => resolve(root, `ios/native/ios/Sources/${file}.swift`))],
      dependencies: [{ target: 'BrowserWindowHost' }],
      settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: 'chat.lumiverse.browser-window-tests' } },
      scheme: { testTargets: ['BrowserWindowTests'] },
    },
  },
}, null, 2))
const env = { ...process.env, DEVELOPER_DIR: process.env.DEVELOPER_DIR || '/Applications/Xcode.app/Contents/Developer' }
const resultBundle = resolve(directory, `browser-windows-${Date.now()}.xcresult`)
for (const command of [
  ['xcodegen', 'generate', '--spec', 'project.yml'],
  ['xcodebuild', '-quiet', '-project', 'LumiverseBrowserWindows.xcodeproj', '-scheme', 'BrowserWindowTests',
    '-destination', `platform=iOS Simulator,id=${simulator}`, '-derivedDataPath', 'derived',
    '-resultBundlePath', resultBundle, '-parallel-testing-enabled', 'NO', 'test'],
]) {
  const child = Bun.spawn(command, { cwd: directory, env, stdout: 'inherit', stderr: 'inherit' })
  if (await child.exited !== 0) throw new Error('iOS browser window regressions failed')
}
const report = Bun.spawn(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', resultBundle],
  { env, stdout: 'pipe', stderr: 'inherit' })
const summary = JSON.parse(await new Response(report.stdout).text())
if (await report.exited !== 0 || summary.result !== 'Passed' || summary.passedTests !== 5 || summary.skippedTests !== 0)
  throw new Error('All five browser window regressions must execute and pass')
console.log('[ios] OAuth presentation, redirects, opener/storage completion, nested windows, cancellation, and bridge isolation passed.')
console.log(resultBundle)
