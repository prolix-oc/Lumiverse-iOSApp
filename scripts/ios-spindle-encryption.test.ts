import { expect, test } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { createCipheriv, createHash, createHmac } from 'node:crypto';

test('registration-scoped backend ciphertext decrypts in Apple CryptoKit without Keychain access', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'spindle-crypto-'));
  try {
    const root = resolve(import.meta.dir, '..'), executable = join(directory, 'check'), fixture = join(directory, 'input.json');
    const credential = 'a'.repeat(43), registrationId = '11111111-2222-4333-8444-555555555555';
    const hash = createHash('sha256').update(credential).digest();
    const key = createHmac('sha256', hash).update(`lumiverse-spindle-activity:v1:${registrationId}`).digest();
    const keyId = createHash('sha256').update(key).digest('hex').slice(0, 32), nonce = Buffer.alloc(12, 17);
    const cipher = createCipheriv('aes-256-gcm', key, nonce);
    cipher.setAAD(Buffer.from(`lumiverse-apns:v1:chat.lumiverse.ios:development:${keyId}`));
    const ciphertext = Buffer.concat([cipher.update(JSON.stringify({ title: 'Private activity 🦊' })), cipher.final()]);
    writeFileSync(fixture, JSON.stringify({ credential, registrationId, key: key.toString('base64'), envelope: {
      version: 1, keyId, nonce: nonce.toString('base64'), ciphertext: ciphertext.toString('base64'), tag: cipher.getAuthTag().toString('base64'),
    } }));
    const compiler = Bun.spawn(['xcrun', 'swiftc', '-module-cache-path', join(directory, 'cache'),
      resolve(root, 'ios/native/ios/Sources/NotificationSecurity.swift'), resolve(import.meta.dir, 'fixtures/ios-spindle-encryption.swift'), '-o', executable],
      { stdout: 'pipe', stderr: 'pipe' });
    expect(await compiler.exited, await new Response(compiler.stderr).text()).toBe(0);
    const probe = Bun.spawn([executable, fixture], { stdout: 'pipe', stderr: 'pipe' });
    expect(await probe.exited, await new Response(probe.stderr).text()).toBe(0);
  } finally { rmSync(directory, { recursive: true, force: true }); }
}, 120_000);
