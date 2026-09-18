/**
 * E2EFileFormat.ets — .wde 文件格式定义 + 异常类型
 *
 * 与 .feature/tests/E2EFileFormat.pure.ts 等价（生产 ArkTS 版本）。
 *
 * 远端存储格式（REQ-004 F2.4）：
 *   [4 bytes: magic "WDVE" = 0x57 0x44 0x56 0x45]
 *   [12 bytes: header nonce]
 *   [4 bytes: headerCiphertextLen uint32 BE]
 *   [N bytes: headerCiphertext (AES-256-GCM 密文)]
 *   [16 bytes: header tag]
 *   [N × chunks] chunk_data = 12B nonce + (variable) ciphertext + 16B tag
 *
 * header plaintext（被 AES-GCM 加密）：
 *   - orig_name (utf-8, 0x00 终止)
 *   - orig_size (uint64 BE)
 *   - chunk_count (uint32 BE)
 */

export const MAGIC: number[] = [0x57, 0x44, 0x56, 0x45]; // "WDVE"
export const VERSION = 1;
export const NONCE_LEN = 12;
export const TAG_LEN = 16;
export const CHUNK_SIZE = 4 * 1024 * 1024; // 4MB
export const FILENAME_EXT = '.wde';
export const HEADER_OVERHEAD = 4 + NONCE_LEN + 4 + TAG_LEN; // 36 bytes (excluding headerCiphertextLen)
export const CHUNK_OVERHEAD = NONCE_LEN + TAG_LEN; // 28 bytes per chunk

/**
 * 异常：tag 校验失败 / 文件被破坏 / chunk 边界错位 / 主密码错误。
 * 一律用此异常，**不暴露原因**（防侧信道）。
 */
export class E2E_AUTH_ERROR extends Error {
  constructor(msg: string = 'e2e auth failed') {
    super(msg);
    this.name = 'E2E_AUTH_ERROR';
  }
}

/**
 * 校验文件以 magic "WDVE" 起头
 */
export function checkMagic(bytes: Uint8Array): void {
  if (bytes.length < 4) {
    throw new E2E_AUTH_ERROR('file too small for magic');
  }
  for (let i = 0; i < 4; i++) {
    if (bytes[i] !== MAGIC[i]) {
      throw new E2E_AUTH_ERROR('bad magic');
    }
  }
}