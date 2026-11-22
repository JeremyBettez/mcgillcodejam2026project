// Exports the Godot project to godot/build/web and adds the browser glue.
// Usage: npm run export:web   (set GODOT_BIN to override the Godot executable)
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, rmSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const project = join(root, 'godot');
const out = join(project, 'build', 'web');
const godot = process.env.GODOT_BIN
  || 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Godot Engine\\godot.windows.opt.tools.64.exe';

if (!existsSync(godot)) {
  console.error(`Godot not found at ${godot}. Set GODOT_BIN to your Godot 4.7.2 executable.`);
  process.exit(1);
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

console.log('[export-web] exporting with Godot...');
const result = spawnSync(godot, ['--headless', '--path', project, '--export-release', 'Web', 'build/web/index.html'], {
  encoding: 'utf8',
});
const log = `${result.stdout ?? ''}${result.stderr ?? ''}`;
const problems = log.split('\n').filter((l) => /ERROR|SCRIPT ERROR/.test(l) && !/yhde|leaked|resources still in use/i.test(l));
if (problems.length) console.error(problems.join('\n'));

const index = join(out, 'index.html');
if (result.status !== 0 || !existsSync(index)) {
  console.error(`[export-web] export failed (exit ${result.status}).`);
  process.exit(1);
}

copyFileSync(join(project, 'web', 'photo-town.js'), join(out, 'photo-town.js'));

const pck = join(out, 'index.pck');
const mb = (f) => (existsSync(f) ? (statSync(f).size / 1048576).toFixed(1) : '?');
console.log(`[export-web] done: ${out}`);
console.log(`[export-web] index.wasm ${mb(join(out, 'index.wasm'))} MB, index.pck ${mb(pck)} MB`);
