#!/usr/bin/env node
/**
 * encrypt-helper.mjs — REQ-004 integration test helper
 *
 * 用法（命令行）：
 *   node encrypt-helper.mjs encrypt  <password> <salt-hex> <input-file> <output-file> <orig-name>
 *   node encrypt-helper.mjs decrypt  <password> <salt-hex> <input-file> <output-file>
 *   node encrypt-helper.mjs encrypt-name <password> <salt-hex> <orig-name>
 *   node encrypt-helper.mjs decrypt-name <password> <salt-hex> <enc-name>
 *   node encrypt-helper.mjs derive    <password> <salt-hex>     -> 输出 masterKey hex + null/存在
 *   node encrypt-helper.mjs tamper    <input-file> <offset> <output-file>
 *
 * 密码派生 + AES-256-GCM 都走 Node crypto（OpenSSL）保证正确性。
 *
 * 失败 → exit 1 + stderr 错误
 */

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';

const ITERATIONS = 100_000;
const KEY_BYTES = 32;
const SALT_BYTES = 16;
const CHUNK_SIZE = 4 * 1024 * 1024;
const MAGIC = Buffer.from([0x57, 0x44, 0x56, 0x45]); // WDVE
const NONCE_LEN = 12;
const TAG_LEN = 16;
const FILENAME_EXT = '.wde';

function deriveMasterKey(password, salt) {
  return crypto.pbkdf2Sync(password, salt, ITERATIONS, KEY_BYTES, 'sha256');
}

function aesGcmEncrypt(key, nonce, plaintext, aad) {
  const c = crypto.createCipheriv('aes-256-gcm', key, nonce);
  if (aad && aad.length > 0) c.setAAD(aad);
  const ct = Buffer.concat([c.update(plaintext), c.final()]);
  const tag = c.getAuthTag();
  return { ciphertext: ct, tag };
}

function aesGcmDecrypt(key, nonce, ciphertext, tag, aad) {
  const d = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  d.setAuthTag(tag);
  if (aad && aad.length > 0) d.setAAD(aad);
  return Buffer.concat([d.update(ciphertext), d.final()]);
}

function encryptFile(inputPath, outputPath, masterKey, origName) {
  const data = fs.readFileSync(inputPath);
  const origSize = data.length;
  const chunkCount = origSize === 0 ? 1 : Math.ceil(origSize / CHUNK_SIZE);
  const headerPlain = encodeHeaderPlaintext(origName, origSize, chunkCount);
  const headerNonce = crypto.randomBytes(NONCE_LEN);
  const { ciphertext: hCt, tag: hTag } = aesGcmEncrypt(masterKey, headerNonce, headerPlain, Buffer.alloc(0));
  const out = [];
  out.push(MAGIC);
  out.push(headerNonce);
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(hCt.length, 0);
  out.push(lenBuf);
  out.push(hCt);
  out.push(hTag);
  for (let i = 0; i < chunkCount; i++) {
    const start = i * CHUNK_SIZE;
    const end = Math.min(data.length, start + CHUNK_SIZE);
    const chunk = data.subarray(start, end);
    const nonce = crypto.randomBytes(NONCE_LEN);
    const { ciphertext, tag } = aesGcmEncrypt(masterKey, nonce, chunk, Buffer.alloc(0));
    out.push(nonce);
    out.push(ciphertext);
    out.push(tag);
  }
  fs.writeFileSync(outputPath, Buffer.concat(out));
}

function decryptFile(inputPath, outputPath, masterKey) {
  const buf = fs.readFileSync(inputPath);
  // magic
  if (buf.length < 4 + NONCE_LEN + 4 + TAG_LEN) throw new Error('file too small');
  for (let i = 0; i < 4; i++) {
    if (buf[i] !== MAGIC[i]) throw new Error('bad magic');
  }
  const headerNonce = buf.subarray(4, 4 + NONCE_LEN);
  const headerCtLen = buf.readUInt32BE(4 + NONCE_LEN);
  const headerCt = buf.subarray(4 + NONCE_LEN + 4, 4 + NONCE_LEN + 4 + headerCtLen);
  const headerTag = buf.subarray(4 + NONCE_LEN + 4 + headerCtLen, 4 + NONCE_LEN + 4 + headerCtLen + TAG_LEN);
  const headerPlain = aesGcmDecrypt(masterKey, headerNonce, headerCt, headerTag, Buffer.alloc(0));
  const decoded = decodeHeaderPlaintext(headerPlain);
  const bodyOff = 4 + NONCE_LEN + 4 + headerCtLen + TAG_LEN;
  const out = Buffer.alloc(decoded.size);
  let pos = 0;
  for (let i = 0; i < decoded.chunkCount; i++) {
    const nonce = buf.subarray(bodyOff, bodyOff + NONCE_LEN);
    const expected = Math.min(CHUNK_SIZE, decoded.size - pos);
    const ct = buf.subarray(bodyOff + NONCE_LEN, bodyOff + NONCE_LEN + expected);
    const tag = buf.subarray(bodyOff + NONCE_LEN + expected, bodyOff + NONCE_LEN + expected + TAG_LEN);
    const plain = aesGcmDecrypt(masterKey, nonce, ct, tag, Buffer.alloc(0));
    plain.copy(out, pos);
    pos += plain.length;
  }
  fs.writeFileSync(outputPath, out);
  return decoded;
}

function encryptFilename(name, masterKey) {
  const aad = Buffer.from('wdv-name');
  const nonce = crypto.randomBytes(NONCE_LEN);
  const { ciphertext, tag } = aesGcmEncrypt(masterKey, nonce, Buffer.from(name, 'utf-8'), aad);
  const blob = Buffer.concat([ciphertext, nonce, tag]);
  return blob.toString('base64url') + FILENAME_EXT;
}

function decryptFilename(blob, masterKey) {
  let b64 = blob;
  if (b64.endsWith(FILENAME_EXT)) b64 = b64.slice(0, -FILENAME_EXT.length);
  const bytes = Buffer.from(b64, 'base64url');
  const ctLen = bytes.length - NONCE_LEN - TAG_LEN;
  const ct = bytes.subarray(0, ctLen);
  const nonce = bytes.subarray(ctLen, ctLen + NONCE_LEN);
  const tag = bytes.subarray(ctLen + NONCE_LEN);
  const aad = Buffer.from('wdv-name');
  const plain = aesGcmDecrypt(masterKey, nonce, ct, tag, aad);
  return plain.toString('utf-8');
}

function encodeHeaderPlaintext(name, size, chunkCount) {
  const nameBytes = Buffer.from(name, 'utf-8');
  const out = Buffer.alloc(nameBytes.length + 1 + 8 + 4);
  let off = 0;
  nameBytes.copy(out, off); off += nameBytes.length;
  out[off++] = 0;
  // size uint64 BE (Node 不直接支持 64 位写，用 8 字节手工写)
  const big = BigInt(size);
  for (let i = 0; i < 8; i++) out[off + i] = Number((big >> BigInt((7 - i) * 8)) & 0xffn);
  off += 8;
  out.writeUInt32BE(chunkCount, off);
  return out;
}

function decodeHeaderPlaintext(b) {
  let cursor = 0;
  let nameEnd = cursor;
  while (nameEnd < b.length && b[nameEnd] !== 0) nameEnd++;
  const name = b.subarray(cursor, nameEnd).toString('utf-8');
  cursor = nameEnd + 1;
  let size = 0;
  for (let i = 0; i < 8; i++) size = size * 256 + b[cursor + i];
  cursor += 8;
  const chunkCount = b.readUInt32BE(cursor);
  return { name, size, chunkCount };
}

// ──────────────────────────────────────────────────────────────────────
// CLI 入口
// ──────────────────────────────────────────────────────────────────────

const [, , cmd, ...args] = process.argv;

try {
  switch (cmd) {
    case 'encrypt': {
      const [password, saltHex, inputFile, outputFile, origName] = args;
      const salt = Buffer.from(saltHex, 'hex');
      if (salt.length !== SALT_BYTES) throw new Error('bad salt length');
      const key = deriveMasterKey(password, salt);
      encryptFile(inputFile, outputFile, key, origName);
      console.log(JSON.stringify({ ok: true, action: 'encrypt', outputBytes: fs.statSync(outputFile).size, name: origName }));
      break;
    }
    case 'decrypt': {
      const [password, saltHex, inputFile, outputFile] = args;
      const salt = Buffer.from(saltHex, 'hex');
      const key = deriveMasterKey(password, salt);
      const r = decryptFile(inputFile, outputFile, key);
      console.log(JSON.stringify({ ok: true, action: 'decrypt', name: r.name, size: r.size }));
      break;
    }
    case 'encrypt-name': {
      const [password, saltHex, origName] = args;
      const salt = Buffer.from(saltHex, 'hex');
      const key = deriveMasterKey(password, salt);
      const enc = encryptFilename(origName, key);
      console.log(enc);
      break;
    }
    case 'decrypt-name': {
      const [password, saltHex, encName] = args;
      const salt = Buffer.from(saltHex, 'hex');
      const key = deriveMasterKey(password, salt);
      const name = decryptFilename(encName, key);
      console.log(name);
      break;
    }
    case 'derive': {
      const [password, saltHex] = args;
      const salt = Buffer.from(saltHex, 'hex');
      const key = deriveMasterKey(password, salt);
      console.log(key.toString('hex'));
      break;
    }
    case 'tamper': {
      const [inputFile, offsetStr, outputFile] = args;
      const buf = fs.readFileSync(inputFile);
      const offset = parseInt(offsetStr, 10);
      buf[offset] = (buf[offset] + 1) & 0xff;
      fs.writeFileSync(outputFile, buf);
      console.log(JSON.stringify({ ok: true, action: 'tamper', offset, outputBytes: buf.length }));
      break;
    }
    default:
      console.error('unknown command: ' + cmd);
      process.exit(2);
  }
} catch (e) {
  console.error(JSON.stringify({ ok: false, error: (e instanceof Error ? e.message : String(e)) }));
  process.exit(1);
}