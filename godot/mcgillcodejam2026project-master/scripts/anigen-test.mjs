// Sends one photo through the AniGen Hugging Face Space and saves the rigged GLB.
// Usage: npm run anigen -- photos/demo.jpg renders/demo
// Put HF_TOKEN=hf_... in .env.local (gitignored) for more ZeroGPU quota.
// The photo is uploaded to Hugging Face. Only use photos of people who agreed.
import { Client, handle_file } from '@gradio/client';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { basename } from 'node:path';

const SPACE = 'VAST-AI/AniGen';
const [photoPath = 'photos/demo.jpg', outDir = 'renders/demo'] = process.argv.slice(2);

// Phone-friendly output: keep ~2% of the triangles and a small texture.
const EXTRACT = { texture_size: 512, simplify_ratio: 0.98, fill_holes: true };

const log = (msg) => console.log(`[${new Date().toLocaleTimeString()}] ${msg}`);

async function download(file, dest) {
  const url = file?.url ?? file;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`download failed ${res.status} for ${url}`);
  await writeFile(dest, Buffer.from(await res.arrayBuffer()));
  log(`saved ${dest} (${(res.headers.get('content-length') / 1024 || 0).toFixed(0)} KB)`);
}

async function main() {
  await mkdir(outDir, { recursive: true });
  const photo = new Blob([await readFile(photoPath)], { type: 'image/jpeg' });

  log(`connecting to ${SPACE}`);
  const app = await Client.connect(SPACE, {
    events: ['data', 'status'],
    token: process.env.HF_TOKEN || undefined,
  });

  // Same client = same session, so the Space's hidden per-session state carries between steps.
  log('starting session');
  await app.predict('/start_session', {});

  log(`step 1/3: background removal + crop (${basename(photoPath)})`);
  const prep = await app.predict('/prepare_input_for_generation', { image: handle_file(photo) });
  await download(prep.data[0], `${outDir}/processed.png`);

  log('step 2/3: generating shape + skeleton (GPU, up to ~2 min)');
  const gen = await app.predict('/generate_preview', {
    seed: 42,
    ss_model_name: 'ss_flow_duet',
    slat_model_name: 'slat_flow_auto',
    ss_guidance_strength: 7.5,
    ss_sampling_steps: 25,
    slat_guidance_strength: 3.0,
    slat_sampling_steps: 25,
    joints_density: 1,
  });
  log(`preview status: ${gen.data[2]}`);

  log('step 3/3: simplify + texture bake + export GLB (GPU, up to ~2 min)');
  const ext = await app.predict('/extract_glb', EXTRACT);
  log(`extract status: ${ext.data[2]}`);
  await download(ext.data[0], `${outDir}/mesh.glb`);
  await download(ext.data[1], `${outDir}/skeleton.glb`);
  log('done');
}

main().catch((err) => {
  console.error('FAILED:', err?.message ?? err);
  process.exit(1);
});
