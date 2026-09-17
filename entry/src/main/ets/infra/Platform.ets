/**
 * Platform.ets — 运行时平台检测与抽象
 *
 * 关键点（参考 .docs/api-survey.md）：
 * - HarmonyOS 4.2 = API 9
 * - HarmonyOS NEXT = API 12+
 * - 不同平台 PhotoAccess / KeyStore / WorkScheduler / AVPlayer 包路径与 API 形态差异很大
 *
 * 设计：本文件不直接 @import 平台特异包（避免编译期报错）。
 * 而是导出抽象 token（如 isNext, getPlatformName），调用方根据 token 用 dynamic import
 * 加载对应平台模块（见 api-survey.md "推荐用法" 模板）。
 */

// 在鸿蒙上，`@ohos.application.ability` 提供 platform.version / sdkVersion
// 在 NEXT 上，等价信息来自 `@kit.AbilityKit` 的 deviceInfo
// 这里统一封装：失败时按最严的 NEXT 行为兜底（更安全）

declare const require: (id: string) => any;

// 平台 SDK 版本号
let cachedSdkVersion: number | null = null;

function readSdkVersion(): number {
  if (cachedSdkVersion !== null) {
    return cachedSdkVersion;
  }
  try {
    // 4.2 路径
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const app = require('@ohos.application.ability');
    const v = (app?.default?.Context?.versionCode) ?? 0;
    cachedSdkVersion = Number(v) || 9;
  } catch (_e) {
    cachedSdkVersion = 12;
  }
  return cachedSdkVersion;
}

/** 是否运行在 HarmonyOS NEXT（API 12+） */
export const isNext: boolean = (() => {
  try {
    return readSdkVersion() >= 12;
  } catch (_e) {
    return false;
  }
})();

/** 平台名（用于日志） */
export const PLATFORM_NAME: string = isNext ? 'HarmonyOS NEXT' : 'HarmonyOS 4.2';

/** SDK 主版本号（用于条件编译判断） */
export function sdkVersion(): number {
  return readSdkVersion();
}

/**
 * 加载平台相关模块。
 * 用法：const mod = loadPlatform('@ohos.x' /* 4.2 */, '@kit.X' /* NEXT */);
 *
 * 注意：Dev 编码时需用 Deveco Studio 的 API 切换器确认两个包路径在当前 SDK
 * 都能解析；dynamic import 让 TS 在编译期不会报错（待 DevEco 真机/模拟器验证）。
 */
export async function loadPlatform<T = any>(
  legacySpecifier: string,
  nextSpecifier: string
): Promise<T> {
  const spec = isNext ? nextSpecifier : legacySpecifier;
  // ArkTS runtime 中 `require` 不直接支持动态模块加载，需要 import 形式
  // 这里返回占位 null，由调用方按 isNext 分支自己处理
  return null as unknown as T;
}