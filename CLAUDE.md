# CLAUDE.md

## Project

**Photo Town**: a McGill CodeJam 2026 hackathon demo. A sim-like 3D world that runs in a phone's browser. The player photographs a real person, the photo is turned into a rigged 3D model, and that model joins the player's world as a resident who walks around. Each player's world (all their residents) is saved on their device.

**Scope is demo-only.** Aim for "works reliably on stage," not production. Prefer the simplest thing that looks good. The world starts as a blank space; the photo → 3D resident feature comes first.

## Stack

- **Game:** Godot 4.7.2 (Steam build), GDScript, exported to **Web** with the **Compatibility** renderer (WebGL2), threads off, ETC2/ASTC textures. Must run on mid-range phones.
- **Photo → 3D:** [AniGen](https://huggingface.co/spaces/VAST-AI/AniGen) (VAST-AI, MIT code) on a Hugging Face ZeroGPU Space.
- **Relay:** `relay/`, a free CPU Hugging Face Gradio Space we own. It holds `HF_TOKEN` as a secret and calls AniGen. The game never holds a token.
- **Phone glue:** `godot/web/photo-town.js`, called from Godot via `JavaScriptBridge`. It opens the camera/photo picker, shrinks the photo and shows the name prompt.
- **Game ↔ relay:** plain HTTP from GDScript (`relay_client.gd`, Gradio REST: upload → call → event stream → file download). Same code on desktop and web; no JS client.
- **Tooling:** Node + Vite only to serve the web export over HTTPS on the LAN (phones need HTTPS for the camera).

## Commands

```sh
npm install
npm run anigen -- photos/demo.jpg renders/demo   # test AniGen directly (needs HF_TOKEN in .env.local)
npm run export:web                               # export Godot to godot/build/web
npm run serve                                    # http://localhost:5173 (desktop browser)
npm run serve:lan                                # HTTPS on the LAN for phone testing
```

Relay (Python env lives in `relay/.venv`, gitignored; create it with `py -3.13 -m venv relay/.venv` and `relay/.venv/Scripts/python -m pip install gradio==6.31.0`):
- Run locally: `HF_TOKEN=... relay/.venv/Scripts/python relay/app.py` → http://127.0.0.1:7860
- **Test mode, no GPU quota:** set `RELAY_FAKE_GLB=renders/demo/mesh.glb` (and optional `RELAY_FAKE_DELAY=6`); `/generate` then returns that GLB. Never set it on the Space.
- Deploy: `relay/.venv/Scripts/python relay/deploy.py <hf-user>/photo-town-relay` (needs `HF_WRITE_TOKEN` and `HF_TOKEN` in `.env.local`), then put the printed URL in `DEPLOYED_URL` in `relay_client.gd`.

Relay URL used by the game: `?relay=` on the web page → project setting `photo_town/relay_url` → `DEPLOYED_URL` (when the page isn't on localhost) → `http://127.0.0.1:7860`.

## Layout

```
godot/                       Godot project (open this folder in the editor)
godot/scripts/main.gd        world, HUD, pause, add/generate/retry/remove flow, save/restore
godot/scripts/resident.gd    resident entity (wander, name tag + status line, ring)
godot/scripts/procedural_gait.gd  walk cycle + wave/dance, bones found from skeleton structure
godot/scripts/glb_loader.gd  runtime GLB load + normalize to 1.7 m
godot/scripts/relay_client.gd  HTTP client for the relay
godot/scripts/world_store.gd   per-device save (user://world.json + residents/<id>.glb)
godot/scripts/add_resident_form.gd, photo_bridge.gd  photo/name form
godot/scripts/camera_rig.gd  touch/mouse orbit camera, tap detection, focus_on()
godot/scripts/round_icon_button.gd  round HUD buttons with icons drawn in code (no image/emoji assets)
godot/scripts/residentcontrol.gd  teammate WIP (ResidentPlayer), not wired in
godot/web/photo-town.js      browser glue (copied into the export)
godot/demo/resident_demo.glb built-in demo resident (gitignored, real person)
godot/addons/yhde/           YHDE real-time collaboration plugin (editor-only, keep it)
relay/                       Hugging Face Space: app.py (/generate), README.md, deploy.py, test_relay.py
scripts/anigen-test.mjs, scripts/export-web.mjs
photos/, renders/            local test photos and outputs (gitignored)
.env.local                   HF_TOKEN / HF_WRITE_TOKEN (gitignored, never commit or print)
```

Web gotcha: in browsers `emulate_touch_from_mouse` does nothing, so `camera_rig.gd` handles real mouse clicks itself and skips mouse events the browser derives from touches (`DEVICE_ID_EMULATION`).

## AniGen output (verified in Phase 0)

With `simplify_ratio=0.98`, `texture_size=512`: one skinned mesh, ~2.4k triangles, one 512 px PNG texture, ~450 KB GLB, no animations. Y-up, about 1 unit tall, centered on the origin, **faces −Z** (Godot forward). 22 bones with generated names (`joint_0`…`joint_21`), and the names and order change per model, so **never hard-code bone names**. Find limbs from the hierarchy and rest positions instead: the root is the pelvis; its children are two 4-bone leg chains (hip, knee, ankle, toe) and the spine; the spine top branches into two 4-bone arm chains and a 2-bone neck/head. Godot loads it at runtime with `GLTFDocument.append_from_buffer` + `generate_scene`.

AniGen's pipeline is three calls in **one session**: `/start_session`, `/prepare_input_for_generation`, `/generate_preview`, `/extract_glb`. A new client = a new session.

## Key decisions

- **Naming:** players only ever see "friends" (Add a friend, Your friends, Remove friend). In code they are still `Resident` / `residents`.
- **HUD layout** (positions inspired by mobile map games, with our own look): title + status top-left, round Pause top-right; bottom-left teal Friends button (opens the friends list), bottom-right orange camera button to add a friend. Nothing in the bottom centre. Panels (add form, friends list) hide the floating buttons and stop camera drags.

- **Residents:** outer `CharacterBody3D` (position, wandering, collision, `Label3D` name tag, selection ring) + inner `Avatar` (the loaded GLB). Only the avatar animates.
- **Animation:** all procedural, in `procedural_gait.gd`, on bones found from the skeleton's structure (see above). Each frame builds a pose (bone → skeleton-space rotation) for the walk and for the current action (`wave`: right arm up, forearm swinging; `dance`: knee bounce, torso sway/twist, alternating arm pumps, head bob) and slerps between them. Friends sometimes wave/dance on their own when idle; tapping a friend offers Wave/Dance buttons, and they turn to face the camera. Placeholders/unrecognized skeletons fall back to rocking (wave) or hop-and-spin (dance).
- **Pick up & drop:** press and hold a friend for 0.22 s (or start dragging on them) to lift them; they follow the finger at 1.3 m with a ground shadow, the whole body swings from the head like a damped pendulum driven by acceleration, and the gait's dangle pose flails/lags the limbs (fake ragdoll, no physics bones). While held they turn to face the camera. Letting go keeps the finger's smoothed velocity: a still finger drops them straight down, a flick throws them in an arc (lift added, max 12 m/s) tumbling end over end; they bounce with restitution 0.45, skid to a stop, bounce off the world edge, unwind upright, and the camera follows a thrown friend until they land. Tunables are the THROW_/TUMBLE_/RESTITUTION constants in `resident.gd`. Held/thrown motion runs in `_process` with ≤1/120 s sub-steps (not the 60 Hz physics tick) so it's smooth at any frame rate; spin has air drag, keeps 80% per bounce, and a critically damped spring rolls the body upright on the ground (a friend counts as landed only once slow and upright). Walking still uses `_physics_process` + `move_and_slide`.
- **Ragdoll limbs:** while held/thrown/skidding, `procedural_gait.gd` `_ragdoll_pose` gives each arm, leg, the torso and head its own damped spring chasing random flail targets (re-targeted faster the more `struggle`), elbows/knees bend on their own springs, spin (`tumble_rate`) flings arms out and tucks legs, and `impulse()` jolts every limb on each bounce. Tunables: LIMB_SPRING / LIMB_DAMP / LIMB_KICK.
- **Dynamic UI:** `ui_fx.gd` has reusable tweens (pop_in, slide_up/down, text_in, add_press_bounce), all running while paused. Every button squashes/bounces when pressed; the camera button pulses (`RoundIconButton.pulse`); the Pause/Play icon twists when it changes; the friends list slides up with rows popping in one by one and slides away when closed; the action bar and the Add-a-friend card pop in; floating buttons pop back after a panel closes; the status line animates whenever its text changes. Use these helpers for any new UI.
- **Works for any future mesh:** every friend is a `Resident`, so all animation/physics applies automatically. Skeleton detection is per model and every part is optional: legs, arms (traced from the side-most leaf back to the spine path, so finger bones are fine), spine, neck. Whatever is found animates; with no skeleton (or nothing recognizable) the whole body still walks, waves, dances, dangles and tumbles via the fallback. Verified on the real AniGen model plus synthetic T-pose, arms-down, extra-bones+fingers, no-arms and no-legs skeletons. Any mesh is normalized to 1.7 m tall with feet on the ground by `glb_loader.gd`. A quick tap still selects; dragging empty space still orbits. `camera_rig.gd` decides tap/grab/orbit (`can_grab` callback + `grab_*` signals); the friend under the finger at touch-down is remembered for the grab.
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
- No consent checkbox or Hugging Face notice in the form (removed at the team's request; don't add it back unless asked). Only photograph people who agreed: the photo is sent to Hugging Face (relay + AniGen) to build the model.
- The saved 3D model's texture is derived from the photo, so it is still a likeness of the person; only the model is kept, never the photo.
- The relay shrinks the photo, strips metadata, and deletes it after the request. Never log or store photos.
- Never save the original photo in the game. Save only the generated model.
- Never commit photos, renders or tokens.

## Known limits

- ZeroGPU quota is per Hugging Face account. A free account runs out after a couple of generations per day; plan on HF PRO or a duplicated AniGen Space for demo day.
- The public AniGen Space can be slow or down; the relay retries connecting and returns friendly errors.
