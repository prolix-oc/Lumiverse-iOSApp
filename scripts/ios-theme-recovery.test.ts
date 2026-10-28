import { expect, test } from 'bun:test'
import { mkdirSync } from 'node:fs'
import { resolve } from 'node:path'

test('native theme recovery preserves navigation and restores themes without relying on page code', async () => {
  const root = resolve(import.meta.dir, '..')
  const cache = resolve(root, '.tmp/ios-theme-recovery-tests')
  mkdirSync(cache, { recursive: true })
  const executable = resolve(cache, 'theme-recovery-regression')
  const compiler = Bun.spawn(['xcrun', 'swiftc', '-module-cache-path', cache,
    resolve(root, 'ios/native/ios/Sources/NativeServerOrigin.swift'),
    resolve(root, 'ios/native/ios/Sources/NativeThemeRecovery.swift'),
    resolve(import.meta.dir, 'fixtures/ios-theme-recovery.swift'), '-o', executable],
    { stdout: 'pipe', stderr: 'pipe' })
  const errors = await new Response(compiler.stderr).text()
  expect(await compiler.exited, errors).toBe(0)
  const probe = Bun.spawn([executable], { stdout: 'pipe', stderr: 'pipe' })
  expect(await probe.exited, await new Response(probe.stderr).text()).toBe(0)
}, 120_000)
