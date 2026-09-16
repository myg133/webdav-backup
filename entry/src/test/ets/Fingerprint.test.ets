/**
 * Fingerprint.test.ets — 单元测试：Fingerprint 模块
 *
 * 用 Hypium (`@ohos.hypium`) 框架。
 * 运行：hvigorw test --module entry
 */

import { describe, it, expect } from '@ohos/hypium';
import { sha1Hex, isFingerprintMatch } from '../../main/ets/domain/Fingerprint';

export default function fingerprintTest() {
  describe('Fingerprint.sha1Hex', () => {
    it('computes known SHA-1 for "abc"', 0, () => {
      const bytes = new Uint8Array([0x61, 0x62, 0x63]);
      expect(sha1Hex(bytes)).assertEqual('a9993e364706816aba3e25717850c26c9cd0d89d');
    });

    it('computes known SHA-1 for empty input', 0, () => {
      expect(sha1Hex(new Uint8Array(0))).assertEqual('da39a3ee5e6b4b0d3255bfef95601890afd80709');
    });

    it('returns consistent results for same input', 0, () => {
      const a = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      const b = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(sha1Hex(a)).assertEqual(sha1Hex(b));
    });
  });

  describe('Fingerprint.isFingerprintMatch', () => {
    it('returns true on identical size/mtime/hash', 0, () => {
      const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      const b = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      expect(isFingerprintMatch(a, b)).assertEqual(true);
    });

    it('returns false on different size', 0, () => {
      const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      const b = { size: 200, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      expect(isFingerprintMatch(a, b)).assertEqual(false);
    });

    it('returns false on different mtime', 0, () => {
      const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      const b = { size: 100, mtime: 1700000001, hashHead: 'h1', hashTail: 't1' };
      expect(isFingerprintMatch(a, b)).assertEqual(false);
    });

    it('returns false on different head hash', 0, () => {
      const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      const b = { size: 100, mtime: 1700000000, hashHead: 'h2', hashTail: 't1' };
      expect(isFingerprintMatch(a, b)).assertEqual(false);
    });

    it('returns false on different tail hash', 0, () => {
      const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
      const b = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't2' };
      expect(isFingerprintMatch(a, b)).assertEqual(false);
    });
  });
}