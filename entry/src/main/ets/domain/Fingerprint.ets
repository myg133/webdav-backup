/**
 * Fingerprint.ets — 首末 1MB sha1 抽样哈希（F4.2 / AC-06）
 *
 * 设计概要 §3.3：每文件记录 (path, size, mtime, hashHead, hashTail)
 *
 * 大文件策略：
 * - 头部：读前 1MB（head_size = 1MB）
 * - 尾部：读末 1MB（tail_size = 1MB）
 * - 中间：不读（避免 IO 抖动）
 * - 文件 < 1MB：头尾重合，用整文件哈希代替
 *
 * 注意：用 SHA-1（16 字节）+ sha1_hex（40 字符）；不用 SHA-256 以节省存储
 * - 极小概率碰撞可由 size + mtime 二次校验（设计概要 §7 对策）
 */

declare const require: (id: string) => any;

const HEAD_TAIL_SAMPLE = 1024 * 1024; // 1 MiB

export interface FingerprintResult {
  size: number;
  mtime: number;
  hashHead: string;
  hashTail: string;
  sha256?: string;
}

export function computeFingerprint(
  filePath: string,
  sizeOverride?: number,
  mtimeOverride?: number
): Promise<FingerprintResult> {
  return new Promise((resolve, reject) => {
    let fs: any;
    try {
      fs = require('@ohos.file.fs');
    } catch (_e) {
      reject(new Error('fs 模块不可用'));
      return;
    }
    try {
      const stat = fs.statSync(filePath);
      const size = sizeOverride ?? Number(stat.size ?? 0);
      const mtime = mtimeOverride ?? Number(stat.mtime ?? 0);

      const stream = fs.createReadStream(filePath);
      let headBytes: Uint8Array;
      let tailBytes: Uint8Array;

      if (size <= HEAD_TAIL_SAMPLE * 2) {
        // 小文件：整文件读取
        const all = new Uint8Array(size);
        const buf = stream.read(size) ?? new ArrayBuffer(size);
        all.set(buf instanceof ArrayBuffer ? new Uint8Array(buf) : (buf as Uint8Array));
        headBytes = all;
        tailBytes = new Uint8Array(0);
      } else {
        // 大文件：读头 1MB + 末 1MB
        const head = new Uint8Array(HEAD_TAIL_SAMPLE);
        const headBuf = stream.read(HEAD_TAIL_SAMPLE) ?? new ArrayBuffer(HEAD_TAIL_SAMPLE);
        head.set(headBuf instanceof ArrayBuffer ? new Uint8Array(headBuf) : (headBuf as Uint8Array));

        const tail = new Uint8Array(HEAD_TAIL_SAMPLE);
        const tailStart = Math.max(0, size - HEAD_TAIL_SAMPLE);
        fs.seekSync?.(stream, tailStart);
        const tailBuf = stream.read(HEAD_TAIL_SAMPLE) ?? new ArrayBuffer(HEAD_TAIL_SAMPLE);
        tail.set(tailBuf instanceof ArrayBuffer ? new Uint8Array(tailBuf) : (tailBuf as Uint8Array));

        headBytes = head;
        tailBytes = tail;
      }

      const hashHead = sha1Hex(headBytes);
      const hashTail = tailBytes.length === 0 ? hashHead : sha1Hex(tailBytes);

      resolve({ size, mtime, hashHead, hashTail });
    } catch (e) {
      reject(e);
    }
  });
}

/**
 * 增量对账判定（AC-06）：
 * - size 不同 → 文件修改过 → 需重传
 * - size 相同 + mtime 不同 → 文件修改过 → 需重传
 * - size+mtime 都相同 + head/tail hash 一致 → 已备份，跳过
 * - 其他情况 → 重传
 */
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

// SHA-1（160-bit）→ 40 字符十六进制
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
        (padded[chunk + i * 4] << 24) |
        (padded[chunk + i * 4 + 1] << 16) |
        (padded[chunk + i * 4 + 2] << 8) |
        padded[chunk + i * 4 + 3];
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

      const t = (((a << 5) | (a >>> 27)) + f + e + k + W[i]) >>> 0;
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