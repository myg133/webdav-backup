// Lint helper for Hypium .test.ets files — parses with TypeScript
const fs = require('fs');
const path = require('path');
const os = require('os');
const ts = require('D:/ToolCaches/npm/node_modules/typescript');

const srcDir = path.resolve(process.argv[2] || 'D:/MyCodes/android/code/entry/src/test/ets');
const tmpDir = path.join(os.tmpdir(), 'ets-tscheck-' + Date.now());
fs.mkdirSync(tmpDir, { recursive: true });

const shim = "declare module '@ohos/hypium' {\n  export function describe(name: string, fn: () => void): void;\n  export function it(name: string, level: number, fn: () => void): void;\n  export const expect: any;\n}\n";

const files = fs.readdirSync(srcDir).filter(f => f.endsWith('.test.ets'));
let ok = true;
const opts = {
  noEmit: true,
  target: ts.ScriptTarget.ES2020,
  module: ts.ModuleKind.CommonJS,
  strict: false,
  skipLibCheck: true,
};

for (const f of files) {
  const src = fs.readFileSync(path.join(srcDir, f), 'utf8');
  const outPath = path.join(tmpDir, f.replace(/\.ets$/, '.ts'));
  fs.writeFileSync(outPath, shim + src);
  const sf = ts.createSourceFile(f, shim + src, opts.target, true);
  const diagnostics = sf.parseDiagnostics || [];
  if (diagnostics.length) {
    ok = false;
    console.log(`${f}: PARSE ERRORS (${diagnostics.length})`);
    diagnostics.slice(0, 5).forEach(d => {
      const pos = sf.getLineAndCharacterOfPosition(d.start || 0);
      console.log(`  line ${pos.line + 1}: ${ts.flattenDiagnosticMessageText(d.messageText, '\n')}`);
    });
  } else {
    console.log(`${f}: parse OK`);
  }
}

process.exit(ok ? 0 : 1);
