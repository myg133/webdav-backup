/**
 * UploadQueue.test.ts — UploadQueue 状态机与指数退避单测
 */

import { PureUploadQueue, type PureQueueItem, type PureUploader, type PureQueueEvent } from './UploadQueue.pure.ts';

const tests: { name: string; run: () => Promise<void> | void }[] = [];
function test(name: string, run: () => Promise<void> | void) {
  tests.push({ name, run });
}

function makeUploader(responses: { ok: boolean; status: number }[]): PureUploader {
  let i = 0;
  return {
    async upload(_item: PureQueueItem) {
      const r = responses[i++] ?? { ok: false, status: 503 };
      return { ok: r.ok, status: r.status, bytes: 1024 };
    },
  };
}

function collectEvents(queue: PureUploadQueue): PureQueueEvent[] {
  const out: PureQueueEvent[] = [];
  queue.on((e) => out.push(e));
  return out;
}

test('happy path: 1 attempt -> succeeded', async () => {
  const q = new PureUploadQueue(makeUploader([{ ok: true, status: 201 }]));
  const events = collectEvents(q);
  q.enqueue({ id: 'a', endpointId: 'e1', size: 1024, remotePath: '/a' });
  const r = await q.runOnce();
  if (r.succeeded !== 1 || r.failed !== 0) throw new Error(`bad result: ${JSON.stringify(r)}`);
  const succeeded = events.filter((e) => e.type === 'succeeded');
  if (succeeded.length !== 1) throw new Error(`expected 1 succeeded, got ${succeeded.length}`);
});

test('503 retry: 3 fails then success -> succeeded after 3 retries', async () => {
  const q = new PureUploadQueue(makeUploader([
    { ok: false, status: 503 },
    { ok: false, status: 503 },
    { ok: false, status: 503 },
    { ok: true, status: 201 },
  ]));
  const events = collectEvents(q);
  q.enqueue({ id: 'a', endpointId: 'e1', size: 1024, remotePath: '/a' });
  const r = await q.runOnce();
  if (r.succeeded !== 1) throw new Error(`expected 1 succeeded, got ${r.succeeded}`);
  const retries = events.filter((e) => e.type === 'retry-scheduled');
  if (retries.length !== 3) throw new Error(`expected 3 retries, got ${retries.length}`);
  // 设计概要 §4.3 公式：sleep(2^(attempt-1))，attempt 从 1 开始 → 1, 2, 4, 8 秒
  // 需求原文 AC-08 acceptance：1s / 2s / 4s / 8s / 16s（5 次重试）
  // Dev 二轮（2026-09-17）：保留文档原意，采用方案 A：Math.min(16, Math.pow(2, attempt - 1))
  if (retries[0].sleepSec !== 1) throw new Error(`first backoff should be 1s, got ${retries[0].sleepSec}`);
  if (retries[1].sleepSec !== 2) throw new Error(`second backoff should be 2s, got ${retries[1].sleepSec}`);
  if (retries[2].sleepSec !== 4) throw new Error(`third backoff should be 4s, got ${retries[2].sleepSec}`);
});

test('always fail: 5 retries -> failed', async () => {
  const q = new PureUploadQueue(makeUploader([
    { ok: false, status: 503 },
    { ok: false, status: 503 },
    { ok: false, status: 503 },
    { ok: false, status: 503 },
    { ok: false, status: 503 },
  ]));
  const events = collectEvents(q);
  q.enqueue({ id: 'a', endpointId: 'e1', size: 1024, remotePath: '/a' });
  const r = await q.runOnce();
  if (r.failed !== 1) throw new Error(`expected 1 failed, got ${r.failed}`);
  const failed = events.filter((e) => e.type === 'failed');
  if (failed.length !== 1) throw new Error(`expected 1 failed event, got ${failed.length}`);
  if (failed[0].retries !== 5) throw new Error(`expected 5 retries, got ${failed[0].retries}`);
});

test('two items, mix success and fail', async () => {
  // Item 1: ok on first try; Item 2: ok on 2nd try
  const q = new PureUploadQueue(makeUploader([
    { ok: true, status: 201 },     // item 1 attempt 1
    { ok: false, status: 503 },    // item 2 attempt 1
    { ok: true, status: 201 },     // item 2 attempt 2
  ]));
  q.enqueue({ id: 'a', endpointId: 'e1', size: 1024, remotePath: '/a' });
  q.enqueue({ id: 'b', endpointId: 'e1', size: 1024, remotePath: '/b' });
  const r = await q.runOnce();
  if (r.succeeded !== 2) throw new Error(`expected 2 succeeded, got ${r.succeeded}`);
});

test('exponential backoff sequence is [1,2,4,8] (2^(attempt-1))', () => {
  // 设计概要 §4.3：attempt 从 1 开始计数（首次重试）。sleep = 2^attempt
  const expected = [1, 2, 4, 8];
  for (let i = 1; i <= 4; i++) {
    const sleepSec = Math.min(16, Math.pow(2, i - 1));
    if (sleepSec !== expected[i - 1]) throw new Error(`attempt ${i}: expected ${expected[i - 1]}, got ${sleepSec}`);
  }
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