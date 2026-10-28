import { expect, test } from 'bun:test'
import { mkdirSync } from 'node:fs'
import { resolve } from 'node:path'

test('native shortcut requests survive startup, expire, and cannot acknowledge a newer action', async () => {
  const root = resolve(import.meta.dir, '..')
  const cache = resolve(root, '.tmp/ios-shortcut-tests')
  mkdirSync(cache, { recursive: true })
  const binary = resolve(cache, 'shortcut-regression')
  const compiler = Bun.spawn(['xcrun', 'swiftc', '-module-cache-path', cache,
    resolve(root, 'ios/native/ios/Sources/NavigationShortcutInbox.swift'),
    resolve(import.meta.dir, 'fixtures/ios-shortcuts.swift'), '-o', binary], { stdout: 'pipe', stderr: 'pipe' })
  expect(await compiler.exited, await new Response(compiler.stderr).text()).toBe(0)
  const probe = Bun.spawn([binary], { stdout: 'pipe', stderr: 'pipe' })
  expect(await probe.exited, await new Response(probe.stderr).text()).toBe(0)
}, 120_000)
