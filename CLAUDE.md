# CLAUDE.md

## Project

**Photo Town**: a McGill CodeJam 2026 hackathon demo. A sim-like 3D world that runs in a phone's browser. The player photographs a real person, the photo is turned into a rigged 3D model, and that model joins the player's world as a resident who walks around. Each player's world (all their residents) is saved on their device.

**Scope is demo-only.** Aim for "works reliably on stage," not production. Prefer the simplest thing that looks good. The world starts as a blank space; the photo → 3D resident feature comes first.

## Stack

- **Game:** Godot 4.7.2 (Steam build), GDScript, exported to **Web** with the **Compatibility** renderer (WebGL2), threads off, ETC2/ASTC textures. Must run on mid-range phones.
- **Photo → 3D:** [AniGen](https://huggingface.co/spaces/VAST-AI/AniGen) (VAST-AI, MIT code) on a Hugging Face ZeroGPU Space.
- **Relay:** `relay/`, a free CPU Hugging Face Gradio Space we own. It holds `HF_TOKEN` as a secret and calls AniGen. The game never holds a token.
- **Phone glue:** a small JS file in the web export, called from Godot via `JavaScriptBridge`. It opens the camera and calls the relay with `@gradio/client`.
- **Tooling:** Node + Vite only to serve the web export over HTTPS on the LAN (phones need HTTPS for the camera).

## Commands

```sh
npm install
npm run anigen -- photos/demo.jpg renders/demo   # test AniGen directly (needs HF_TOKEN in .env.local)
npm run export:web                               # export Godot to godot/build/web
npm run serve:lan                                # HTTPS on the LAN for phone testing
```

Relay locally: `cd relay && pip install gradio==6.31.0 && HF_TOKEN=... python app.py`, test with `python relay/test_relay.py http://127.0.0.1:7860 photos/demo.jpg renders/relay`.

## Layout

```
godot/                 Godot project (open this folder in the editor)
godot/addons/yhde/     YHDE real-time collaboration plugin (editor-only, keep it)
relay/                 Hugging Face Space: app.py (/generate endpoint), README.md (Space card)
scripts/anigen-test.mjs  Node test that calls AniGen directly
photos/, renders/      local test photos and outputs (gitignored)
.env.local             HF_TOKEN (gitignored, never commit or print it)
```

## AniGen output (verified in Phase 0)

With `simplify_ratio=0.98`, `texture_size=512`: one skinned mesh, ~2.4k triangles, one 512 px PNG texture, ~450 KB GLB, no animations. Y-up, about 1 unit tall, centered on the origin, **faces −Z** (Godot forward). 22 bones with generated names (`joint_0`…`joint_21`), and the names and order change per model, so **never hard-code bone names**. Find limbs from the hierarchy and rest positions instead: the root is the pelvis; its children are two 4-bone leg chains (hip, knee, ankle, toe) and the spine; the spine top branches into two 4-bone arm chains and a 2-bone neck/head. Godot loads it at runtime with `GLTFDocument.append_from_buffer` + `generate_scene`.

AniGen's pipeline is three calls in **one session**: `/start_session`, `/prepare_input_for_generation`, `/generate_preview`, `/extract_glb`. A new client = a new session.

## Key decisions

- **Residents:** outer `CharacterBody3D` (position, wandering, collision, `Label3D` name tag, selection ring) + inner `Avatar` (the loaded GLB). Only the avatar animates.
- **Walk animation:** procedural gait on the skeleton found from its structure (see above), with a whole-body bob fallback if the skeleton can't be classified.
- **Placeholder** resident walks while a model generates (1–3 min); it is swapped for the GLB when ready.
- **Saving:** per device, in `user://` (IndexedDB on web): `world.json` plus `residents/<id>.glb`. No accounts.
- Keep each resident under ~5k triangles and cap the world at ~15 residents for phones.

## Conventions

- GDScript with static types, tabs (Godot default). JS/Python: 2-space JS, 4-space Python, single quotes.
- Every API that can be missing or fail needs a graceful fallback: camera, network, relay, quota, storage, GLB loading. The demo must never hard-crash; show a friendly message instead.
- UI must work at phone width (portrait) and with touch.
- Pin exact versions for every dependency and CDN URL. Use releases at least two weeks old.

## Privacy

The app handles photos of real people:
- Require the consent checkbox before generating. Its text must say the photo is sent to Hugging Face for processing.
- The relay shrinks the photo, strips metadata, and deletes it after the request. Never log or store photos.
- Never save the original photo in the game. Save only the generated model.
- Never commit photos, renders or tokens.

## Known limits

- ZeroGPU quota is per Hugging Face account. A free account runs out after a couple of generations per day; plan on HF PRO or a duplicated AniGen Space for demo day.
- The public AniGen Space can be slow or down; the relay retries connecting and returns friendly errors.
