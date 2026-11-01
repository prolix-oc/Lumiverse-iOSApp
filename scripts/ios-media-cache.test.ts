import { expect, test } from 'bun:test'
import { mkdirSync } from 'node:fs'
import { resolve } from 'node:path'

test('native media cache persists scoped tiers, expires, evicts and rejects unsafe entries', async () => {
  const root = resolve(import.meta.dir, '..')
  const scratch = resolve(root, '.tmp/ios-media-cache-unit')
  mkdirSync(scratch, { recursive: true })
  const executable = resolve(scratch, 'media-cache-tests')
  const compile = Bun.spawn(['xcrun', 'swiftc', '-module-cache-path', scratch,
    ...['NativeServerOrigin', 'NativeMediaCacheStore'].map(name => resolve(root, `ios/native/ios/Sources/${name}.swift`)),
    resolve(import.meta.dir, 'fixtures/ios-media-cache.swift'), '-o', executable], { stdout: 'pipe', stderr: 'pipe' })
  const errors = await new Response(compile.stderr).text()
  expect(await compile.exited, errors).toBe(0)
  const run = Bun.spawn([executable], { stdout: 'pipe', stderr: 'pipe' })
  const failure = await new Response(run.stderr).text()
  expect(await run.exited, failure).toBe(0)
}, 120_000)
