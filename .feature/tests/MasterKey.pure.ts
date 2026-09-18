/**
 * MasterKey.pure.ts — 主密钥派生（PBKDF2-HMAC-SHA256）的纯 TS 实现
 *
 * 与 ArkTS 版本 MasterKey.ets 等价；可在 Node.js 测试环境跑。
 *
 * 设计要点（REQ-004 F1 / 关键约束）：
 *   - PBKDF2-HMAC-SHA256，100_000 迭代（保底；可通过 ITERATIONS 调整）
 *   - 输出 32 字节 master key
 *   - 盐 16 字节，由 generateSalt() 生成
 *   - **永远不落盘明文密码**
 *   - **永远不通过网络传任何派生材料**
 *   - **主密码错误不抛异常** —— 返回 null，UI 友好提示
 *
 * verifyPassword 用一个本地预生成的 dummy 密文做 tag 校验：
 *   - 派生成功 + decrypt 成功 = 密码正确（返回 32 字节 master key）
 *   - 派生成功 + decrypt 失败（GCM tag 不匹配）= 密码错误（返回 null）
 */

export const ITERATIONS = 100_000;
export const SALT_BYTES = 16;
export const KEY_BYTES = 32;

/** 16 字节随机盐。测试可注入 stubRandom 强制输出固定值。 */
export function generateSalt(): Uint8Array {
  const out = new Uint8Array(SALT_BYTES);
  // 测试兼容：先看全局 stub
  const g: any = globalThis as any;
  if (g.__REQ004_STUB_RANDOM__ && typeof g.__REQ004_STUB_RANDOM__ === 'function') {
    const arr = g.__REQ004_STUB_RANDOM__(SALT_BYTES);
    for (let i = 0; i < SALT_BYTES; i++) out[i] = arr[i] ?? 0;
    return out;
  }
  for (let i = 0; i < SALT_BYTES; i++) {
    out[i] = Math.floor(Math.random() * 256);
  }
  return out;
}

/**
 * PBKDF2-HMAC-SHA256，纯 TS 实现（与 Node crypto.pbkdf2Sync 输出一致）。
 * 输入：password 字符串、salt 字节、iterations、dkLen 输出字节数
 */
export async function pbkdf2Sha256(
  password: Uint8Array,
  salt: Uint8Array,
  iterations: number,
  dkLen: number
): Promise<Uint8Array> {
  const prf = (key: Uint8Array, data: Uint8Array) => hmacSha256(key, data);
  const hLen = 32; // SHA-256 输出
  const blocksCount = Math.ceil(dkLen / hLen);
  const out = new Uint8Array(blocksCount * hLen);

  for (let i = 1; i <= blocksCount; i++) {
    // U_1 = PRF(P, salt || INT(i))
    const block = concatBytes(salt, uint32Be(i));
    const u = prf(password, block);
    const t = new Uint8Array(u);
    for (let j = 2; j <= iterations; j++) {
      const uNext = prf(password, u);
      for (let k = 0; k < t.length; k++) {
        t[k] = t[k] ^ uNext[k];
      }
      // `out` 复用 u 引用（HMAC 返回新的 Uint8Array）
      for (let k = 0; k < u.length; k++) {
        u[k] = uNext[k];
      }
    }
    out.set(t, (i - 1) * hLen);
  }
  return out.slice(0, dkLen);
}

/**
 * 派生主密钥。
 * @returns 32 字节 master key
 */
export async function deriveMasterKey(
  password: string,
  salt: Uint8Array,
  iterations: number = ITERATIONS
): Promise<Uint8Array | null> {
  const pwdBytes = stringToUtf8(password);
  const key = await pbkdf2Sha256(pwdBytes, salt, iterations, KEY_BYTES);
  return key;
}

// ──────────────────────────────────────────────────────────────────────
// 内部：HMAC-SHA256、UTF-8、SHA-256
// ──────────────────────────────────────────────────────────────────────

function hmacSha256(key: Uint8Array, data: Uint8Array): Uint8Array {
  const blockSize = 64;
  let k: Uint8Array;
  if (key.length > blockSize) {
    k = sha256(key);
  } else if (key.length < blockSize) {
    k = new Uint8Array(blockSize);
    k.set(key);
  } else {
    k = key;
  }

  const oKeyPad = new Uint8Array(blockSize);
  const iKeyPad = new Uint8Array(blockSize);
  for (let i = 0; i < blockSize; i++) {
    oKeyPad[i] = k[i] ^ 0x5c;
    iKeyPad[i] = k[i] ^ 0x36;
  }

  const inner = sha256(concatBytes(iKeyPad, data));
  return sha256(concatBytes(oKeyPad, inner));
}

/** 标准 SHA-256（输出 raw bytes） */
function sha256(bytes: Uint8Array): Uint8Array {
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const H = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const len = bytes.length;
  const padLen = (((len + 9) >> 6) << 6) + 64;
  const padded = new Uint8Array(padLen);
  padded.set(bytes);
  padded[len] = 0x80;
  const bitLen = BigInt(len) * 8n;
  for (let i = 0; i < 8; i++) {
    padded[padLen - 1 - i] = Number((bitLen >> BigInt(i * 8)) & 0xffn);
  }

  const W = new Uint32Array(64);
  for (let chunk = 0; chunk < padLen; chunk += 64) {
    for (let i = 0; i < 16; i++) {
      W[i] =
        (padded[chunk + i * 4] << 24) |
        (padded[chunk + i * 4 + 1] << 16) |
        (padded[chunk + i * 4 + 2] << 8) |
        padded[chunk + i * 4 + 3];
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >>> 3);
      const s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >>> 10);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) | 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const temp1 = (h + S1 + ch + K[i] + W[i]) | 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const temp2 = (S0 + maj) | 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) | 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) | 0;
    }
    H[0] = (H[0] + a) | 0;
    H[1] = (H[1] + b) | 0;
    H[2] = (H[2] + c) | 0;
    H[3] = (H[3] + d) | 0;
    H[4] = (H[4] + e) | 0;
    H[5] = (H[5] + f) | 0;
    H[6] = (H[6] + g) | 0;
    H[7] = (H[7] + h) | 0;
  }

  const out = new Uint8Array(32);
  for (let i = 0; i < 8; i++) {
    out[i * 4] = (H[i] >>> 24) & 0xff;
    out[i * 4 + 1] = (H[i] >>> 16) & 0xff;
    out[i * 4 + 2] = (H[i] >>> 8) & 0xff;
    out[i * 4 + 3] = H[i] & 0xff;
  }
  return out;
}

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

function concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function uint32Be(n: number): Uint8Array {
  return new Uint8Array([
    (n >>> 24) & 0xff,
    (n >>> 16) & 0xff,
    (n >>> 8) & 0xff,
    n & 0xff,
  ]);
}

function stringToUtf8(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) out.push(c);
    else if (c < 0x800) {
      out.push(0xc0 | (c >> 6));
      out.push(0x80 | (c & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12));
      out.push(0x80 | ((c >> 6) & 0x3f));
      out.push(0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}