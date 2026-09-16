/**
 * Fingerprint.pure.ts — sha1Hex 与 isFingerprintMatch 的纯 TypeScript 版本
 * （与 ArkTS 版本 Fingerprint.ets 等价；可在 Node.js 测试环境跑）
 */

export function sha1Hex(bytes: Uint8Array): string {
  const H = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0];
  const len = bytes.length;
  const padLen = (((len + 9) >> 6) << 6) + 64;
  const padded = new Uint8Array(padLen);
  padded.set(bytes);
  padded[len] = 0x80;
  const bitLen = BigInt(len) * 8n;
  for (let i = 0; i < 8; i++) {
    padded[padLen - 1 - i] = Number((bitLen >> BigInt(i * 8)) & 0xffn);
  }

  const W = new Uint32Array(80);
  for (let chunk = 0; chunk < padLen; chunk += 64) {
    for (let i = 0; i < 16; i++) {
      W[i] =
        ((padded[chunk + i * 4] << 24) >>> 0) |
        ((padded[chunk + i * 4 + 1] << 16) >>> 0) |
        ((padded[chunk + i * 4 + 2] << 8) >>> 0) |
        (padded[chunk + i * 4 + 3] >>> 0);
    }
    for (let i = 16; i < 80; i++) {
      const v = W[i - 3] ^ W[i - 8] ^ W[i - 14] ^ W[i - 16];
      W[i] = ((v << 1) | (v >>> 31)) >>> 0;
    }

    let [a, b, c, d, e] = H;
    for (let i = 0; i < 80; i++) {
      let f: number;
      let k: number;
      if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
      else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
      else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
      else { f = b ^ c ^ d; k = 0xca62c1d6; }

      const t = ((((a << 5) | (a >>> 27)) + f + e + k + W[i]) >>> 0) >>> 0;
      e = d;
      d = c;
      c = ((b << 30) | (b >>> 2)) >>> 0;
      b = a;
      a = t;
    }

    H[0] = (H[0] + a) >>> 0;
    H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0;
    H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0;
  }

  return H.map((x) => (x >>> 0).toString(16).padStart(8, '0')).join('');
}

export function isFingerprintMatch(
  fp: { size: number; mtime: number; hashHead: string; hashTail: string },
  cur: { size: number; mtime: number; hashHead: string; hashTail: string }
): boolean {
  if (fp.size !== cur.size) return false;
  if (fp.mtime !== cur.mtime) return false;
  if (fp.hashHead !== cur.hashHead) return false;
  if (fp.hashTail !== cur.hashTail) return false;
  return true;
}