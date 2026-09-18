/**
 * E2EFileFormat.test.ts — .wde 文件格式 + 头解析单元测试
 *
 * 覆盖（REQ-004 F2.4）：
 *   - 文件以 magic "WDVE" 起头
 *   - 文件过小时抛 E2E_AUTH_ERROR
 *   - 错误的 magic 抛 E2E_AUTH_ERROR
 *   - header plaintext 编码 + 解码 roundtrip（含 unicode）
 *   - chunk count 边界（0 字节 = 1 空 chunk，4MB-1 = 1 chunk，4MB = 1 chunk，4MB+1 = 2 chunks）
 *   - expectedTotalSize 公式正确（多 chunk 总长）
 *
 * 用法：node --experimental-strip-types E2EFileFormat.test.ts
 */

import {
  checkMagic,
  readHeaderRaw,
  encodeHeaderPlaintext,
  decodeHeaderPlaintext,
  calcChunkCount,
  expectedTotalSize,
  MAGIC,
  HEADER_OVERHEAD,
  CHUNK_OVERHEAD,
  NONCE_LEN,
  TAG_LEN,
  E2E_AUTH_ERROR,
} from './E2EFileFormat.pure.ts';
import { encryptFile } from './E2ECrypto.pure.ts';

const tests: { name: string; run: () => Promise<void> | void }[] = [];
function test(name: string, run: () => Promise<void> | void) {
  tests.push({ name, run });
}

test('checkMagic: 4 bytes WDVE = OK', () => {
  checkMagic(new Uint8Array(MAGIC));
});

test('checkMagic: wrong magic throws E2E_AUTH_ERROR', () => {
  let caught = false;
  try {
    checkMagic(new Uint8Array([0x00, 0x00, 0x00, 0x00]));
  } catch (e) {
    caught = (e as Error).name === 'E2E_AUTH_ERROR';
  }
  if (!caught) throw new Error('bad magic was accepted');
});

test('checkMagic: too-short bytes throws E2E_AUTH_ERROR', () => {
  let caught = false;
  try {
    checkMagic(new Uint8Array([0x57, 0x44]));
  } catch (e) {
    caught = (e as Error).name === 'E2E_AUTH_ERROR';
  }
  if (!caught) throw new Error('too-short input was accepted');
});

test('encodeHeaderPlaintext + decodeHeaderPlaintext (ascii)', () => {
  const plaintext = encodeHeaderPlaintext('photo.jpg', 12345, 1);
  const decoded = decodeHeaderPlaintext(plaintext);
  if (decoded.name !== 'photo.jpg') throw new Error(`bad name: ${decoded.name}`);
  if (decoded.size !== 12345) throw new Error(`bad size: ${decoded.size}`);
  if (decoded.chunkCount !== 1) throw new Error(`bad chunkCount: ${decoded.chunkCount}`);
});

test('encodeHeaderPlaintext + decodeHeaderPlaintext (unicode)', () => {
  const orig = '照片-2026-✅.jpg';
  const plaintext = encodeHeaderPlaintext(orig, 100000, 5);
  const decoded = decodeHeaderPlaintext(plaintext);
  if (decoded.name !== orig) throw new Error(`unicode roundtrip failed: ${decoded.name}`);
  if (decoded.size !== 100000) throw new Error('size mismatch');
  if (decoded.chunkCount !== 5) throw new Error('chunkCount mismatch');
});

test('readHeaderRaw: parses encrypted header layout', async () => {
  const key = new Uint8Array(32);
  for (let i = 0; i < 32; i++) key[i] = i;
  const data = new Uint8Array(100);
  for (let i = 0; i < 100; i++) data[i] = i;
  const ct = await encryptFile(data.buffer, 'test.bin', 100, key);
  const bytes = new Uint8Array(ct);

  // 1. magic
  checkMagic(bytes);

  // 2. readHeaderRaw parses layout
  const h = readHeaderRaw(bytes);
  if (h.headerNonce.length !== NONCE_LEN) throw new Error('bad header nonce length');
  if (h.headerCiphertext.length !== h.headerCiphertextLen) throw new Error('headerCiphertext len mismatch');
  if (h.headerTag.length !== TAG_LEN) throw new Error('bad header tag length');
  if (h.bodyStart !== HEADER_OVERHEAD + h.headerCiphertextLen) throw new Error('bad bodyStart');
});

test('readHeaderRaw: truncated header throws E2E_AUTH_ERROR', () => {
  let caught = false;
  try {
    readHeaderRaw(new Uint8Array(MAGIC.length + 4)); // magic + 4 bytes (no body)
  } catch (e) {
    caught = (e as Error).name === 'E2E_AUTH_ERROR';
  }
  if (!caught) throw new Error('truncated header was accepted');
});

test('calcChunkCount: boundaries', () => {
  const cs = 4 * 1024 * 1024; // 4MB
  if (calcChunkCount(0, cs) !== 1) throw new Error('0 bytes should be 1 chunk');
  if (calcChunkCount(1, cs) !== 1) throw new Error('1 byte should be 1 chunk');
  if (calcChunkCount(cs - 1, cs) !== 1) throw new Error('4MB-1 should be 1 chunk');
  if (calcChunkCount(cs, cs) !== 1) throw new Error('4MB should be 1 chunk');
  if (calcChunkCount(cs + 1, cs) !== 2) throw new Error('4MB+1 should be 2 chunks');
  if (calcChunkCount(2 * cs, cs) !== 2) throw new Error('8MB should be 2 chunks');
  if (calcChunkCount(2 * cs + 1, cs) !== 3) throw new Error('8MB+1 should be 3 chunks');
});

test('expectedTotalSize: matches actual encrypted size (1ch)', async () => {
  const key = new Uint8Array(32);
  for (let i = 0; i < 32; i++) key[i] = i;
  const data = new Uint8Array(100);
  const ct = await encryptFile(data.buffer, 'a.bin', 100, key);
  // 实际 size: HEADER_OVERHEAD + headerCiphertextLen + 1 chunk (NONCE + 100 + TAG)
  const h = readHeaderRaw(new Uint8Array(ct));
  const expected = expectedTotalSize(100, 4 * 1024 * 1024, h.headerCiphertextLen);
  if (ct.byteLength !== expected) throw new Error(`size mismatch: actual=${ct.byteLength}, expected=${expected}`);
});

test('expectedTotalSize: matches actual encrypted size (5MB = 2 chunks)', async () => {
  const key = new Uint8Array(32);
  for (let i = 0; i < 32; i++) key[i] = i;
  const data = new Uint8Array(5 * 1024 * 1024);
  const ct = await encryptFile(data.buffer, 'big.bin', data.length, key);
  const h = readHeaderRaw(new Uint8Array(ct));
  const expected = expectedTotalSize(data.length, 4 * 1024 * 1024, h.headerCiphertextLen);
  if (ct.byteLength !== expected) throw new Error(`5MB size mismatch: actual=${ct.byteLength}, expected=${expected}`);
});

test('header plaintext: name length can be 0 (empty name)', () => {
  const plaintext = encodeHeaderPlaintext('', 100, 1);
  const decoded = decodeHeaderPlaintext(plaintext);
  if (decoded.name !== '') throw new Error(`empty name roundtrip failed: "${decoded.name}"`);
  if (decoded.size !== 100) throw new Error('size mismatch');
});

let passed = 0, failed = 0;
(async () => {
  for (const t of tests) {
    try {
      await t.run();
      console.log(`  ✅ ${t.name}`);
      passed += 1;
    } catch (e) {
      console.error(`  ❌ ${t.name}: ${(e as Error).message}`);
      failed += 1;
    }
  }
  console.log(`\n  Total: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
})();