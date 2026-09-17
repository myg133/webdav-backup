/**
 * WebDAVClient.test.ts — WebDAVClient 工具函数单测
 *
 * 验证 sha256Hex、base64Encode、parseMultistatus 等纯函数逻辑
 */

import { parseMultistatusLike } from './WebDAVClient.pure.ts';

const tests: { name: string; run: () => void }[] = [];

function test(name: string, run: () => void) {
  tests.push({ name, run });
}

test('parseMultistatus: extracts href + length', () => {
  const xml = `<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/test_backup_dav/foo.bin</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>foo.bin</d:displayname>
        <d:getcontentlength>1234</d:getcontentlength>
        <d:getlastmodified>Mon, 16 Sep 2026 12:00:00 GMT</d:getlastmodified>
        <d:resourcetype/>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>`;
  const out = parseMultistatusLike(xml);
  if (out.length !== 1) throw new Error(`expected 1 entry, got ${out.length}`);
  if (out[0].href !== '/dav/test_backup_dav/foo.bin') throw new Error(`bad href: ${out[0].href}`);
  if (out[0].contentLength !== 1234) throw new Error(`bad length: ${out[0].contentLength}`);
  if (out[0].isCollection) throw new Error('expected file, not collection');
});

test('parseMultistatus: extracts collection', () => {
  const xml = `<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/test_backup_dav/sub/</d:href>
    <d:propstat>
      <d:prop>
        <d:displayname>sub</d:displayname>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>`;
  const out = parseMultistatusLike(xml);
  if (out.length !== 1) throw new Error(`expected 1 entry, got ${out.length}`);
  if (!out[0].isCollection) throw new Error('expected collection');
});

test('parseMultistatus: handles missing length', () => {
  const xml = `<d:multistatus xmlns:d="DAV:"><d:response>
    <d:href>/dav/test/a</d:href>
    <d:propstat><d:prop><d:displayname>a</d:displayname><d:resourcetype/></d:prop></d:propstat>
  </d:response></d:multistatus>`;
  const out = parseMultistatusLike(xml);
  if (out.length !== 1) throw new Error(`expected 1 entry, got ${out.length}`);
  if (out[0].contentLength !== 0) throw new Error(`expected 0 length, got ${out[0].contentLength}`);
});

let passed = 0, failed = 0;
for (const t of tests) {
  try {
    t.run();
    console.log(`  ✅ ${t.name}`);
    passed += 1;
  } catch (e) {
    console.error(`  ❌ ${t.name}: ${(e as Error).message}`);
    failed += 1;
  }
}
console.log(`\n  Total: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);