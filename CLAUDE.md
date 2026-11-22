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
npm run relay                                    # relay on http://127.0.0.1:7860 with keys from .env.local
npm run relay:test                               # same, no quota/key: demo friend model + sample Quick build recipe
```

Relay (Python env lives in `relay/.venv`, gitignored; create it with `py -3.13 -m venv relay/.venv` and `relay/.venv/Scripts/python -m pip install gradio==6.31.0`):
- Run locally: `npm run relay` (`scripts/run-relay.mjs` loads `.env.local`, tolerating `KEY = value`, and starts `relay/app.py` → http://127.0.0.1:7860; it prints which generators are on, never the keys). `npm run relay:test` turns on the fake modes below.
- **Test mode, no GPU quota:** set `RELAY_FAKE_GLB=renders/demo/mesh.glb` (and optional `RELAY_FAKE_DELAY=6`); `/generate` then returns that GLB. Never set it on the Space.
- **Quick build test mode, no API key:** `RELAY_FAKE_RECIPE=relay/sample_recipe.json`; `/generate_place_recipe` then returns that recipe (with the place's name as its sign).
- Quick build for real needs `ANTHROPIC_API_KEY` in the relay's environment (locally) or as a Space secret (`deploy.py` sets it from `.env.local` when present). The relay pins `anthropic==2.6.0` (`relay/requirements.txt`; also installed in `relay/.venv`).
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
godot/scripts/camera_rig.gd  fixed-angle camera: pan (ground stays under the finger) with flick glide, smooth zoom, tap/grab detection, focus_on(), bounds, velocity
godot/scripts/district.gd    District: a neighbourhood with a row of 3 lots facing the camera, signpost, empty-lot plots; SLOTS grid
godot/scripts/recipe_model.gd  RecipeModel: builds a Quick build place from a JSON recipe (block, wings, floors of windows, door, columns + pediment, awning, roof style, tower, sign, trees, flag colours); clamps every field
godot/scripts/cafe_models.gd, oratory_model.gd  Starbucks / McDonald's storefronts and Saint Joseph's Oratory, built in code
godot/scripts/brand_logos.gd  logo textures drawn in code (arches, Starbucks siren badge) + quad() helper
godot/scripts/round_icon_button.gd  round HUD buttons with icons drawn in code, or a `picture` clipped to a circle
godot/icons/pin.png, camera.png  painted pin/camera stickers (team art cut out of screenshots, cream border) on the Locations / add-a-friend buttons
godot/icons/goose.png        app mascot sticker (travel goose cut out of the team's painting, cream border, transparent PNG), on the Friends button
godot/scripts/residentcontrol.gd  teammate WIP (ResidentPlayer), not wired in
godot/web/photo-town.js      browser glue (copied into the export)
godot/demo/resident_demo.glb built-in demo resident (gitignored, real person)
godot/addons/yhde/           YHDE real-time collaboration plugin (editor-only, keep it)
relay/                       Hugging Face Space: app.py (/generate, /generate_place, /generate_place_recipe), README.md, requirements.txt, deploy.py, test_relay.py, sample_recipe.json
scripts/anigen-test.mjs, scripts/export-web.mjs
photos/, renders/            local test photos and outputs (gitignored)
.env.local                   HF_TOKEN / HF_WRITE_TOKEN / ANTHROPIC_API_KEY (gitignored, never commit or print)
```

Web gotcha: in browsers `emulate_touch_from_mouse` does nothing, so `camera_rig.gd` handles real mouse clicks itself and skips mouse events the browser derives from touches (`DEVICE_ID_EMULATION`).

## AniGen output (verified in Phase 0)

With `simplify_ratio=0.98`, `texture_size=512`: one skinned mesh, ~2.4k triangles, one 512 px PNG texture, ~450 KB GLB, no animations. Y-up, about 1 unit tall, centered on the origin, **faces −Z** (Godot forward). 22 bones with generated names (`joint_0`…`joint_21`), and the names and order change per model, so **never hard-code bone names**. Find limbs from the hierarchy and rest positions instead: the root is the pelvis; its children are two 4-bone leg chains (hip, knee, ankle, toe) and the spine; the spine top branches into two 4-bone arm chains and a 2-bone neck/head. Godot loads it at runtime with `GLTFDocument.append_from_buffer` + `generate_scene`.

AniGen's pipeline is three calls in **one session**: `/start_session`, `/prepare_input_for_generation`, `/generate_preview`, `/extract_glb`. A new client = a new session.

## Key decisions

- **Town layout (districts):** the town is a grid of `District`s (Montreal neighbourhoods, `District.SLOTS`: Downtown (0,0,0), Old Montréal (0,0,26), The Islands (40,0,26), Côte-des-Neiges (-40,0,0), then Plateau, Mile End, Outremont, Saint-Henri). Each district is a tinted lawn with 3 lots at x -12/0/+12 (filled middle, left, right), a wooden signpost with its name, and dirt plots on empty lots. **Every location faces +Z** (the fixed camera). Built-ins: Downtown = Starbucks, McGill, McDonald's; Old Montréal = Old Port; The Islands = Parc Jean-Drapeau; Côte-des-Neiges = Marianopolis College (`marianopolis_model.gd`, a hand-written recipe built with RecipeModel) and Saint Joseph's Oratory. A new place takes the first free lot (`_find_lot`), creating the next district when all are full; world.json places store `district` + `lot` (older saves get a free lot). `_update_camera_bounds` keeps panning over existing districts. **Add empty land:** the Locations list's "+ Add empty land (3 plots)" (`_add_land`) creates the next unused slot's district, flies the camera there and plays a golden ring on each plot; every district id is saved in world.json `"land"` and restored first (`_restore_land`). 14 slots (Verdun, Rosemont, Westmount, Little Italy, Hochelaga, Lachine added); ground disc WORLD_RADIUS 110. MAX_PLACES 20. Ground disc radius WORLD_RADIUS 110; friends without a home wander within `wander_radius` 24 of the middle. Brand places use brand colours, name signs and simple emblems drawn in code by `brand_logos.gd` (BrandLogos: golden arches; a round green badge with a simplified twin-tailed siren), shown on unshaded quads.
- **Moving buildings:** long-press a building (0.45 s, `CameraRig.can_hold_grab` / LONG_HOLD; a drag that starts sooner still pans) to lift it; it floats under the finger (walls off), the view edge-pans near the screen edges, and a yellow disc marks the nearest lot within 9 m. Drop on a free lot to move, on another building to swap (`_relocate`), anywhere else to put it back. Landing glides with a bounce and a golden ring burst (`_ring_burst`: two expanding, rising, fading rings + gold sparkles). Friends of moved places walk to the new spot. Built-in plot changes save as world.json `"layout"` and are applied by `_restore_layout` before player places are restored.
- **Locations:** `location.gd` (class `Location`): a 3D model + a hangout area (radius, lighter lawn) + a building footprint. Friends with `home` set pick wander targets inside the area outside the footprint, and walk back if thrown away. Built-in: McGill University (`mcgill_model.gd`, Arts-Building-style low-poly model built in code, StaticBody walls on physics layer 1) in Downtown; Kevin's home is McGill. Also built in (all Montreal): **Old Port** (`old_port_model.gd`, white Ferris wheel slowly turning with level pastel gondolas, boardwalk, quay, river) in Old Montréal and **Parc Jean-Drapeau** (`jean_drapeau_model.gd`, the Biosphere geodesic dome: icosphere struts in one MultiMesh over pale glass, museum inside, park trees) in The Islands, via `_add_builtin(id, name, model, footprint, district, radius, view_distance)`; shared helpers in `model_kit.gd` (ModelKit: mat/box/cylinder/beam/tree/sign/walls). `Location.view_distance` overrides the fly-to camera distance for tall/round models. Friend homes save as `"home": "<location id>"` in world.json. **Add a location:** Locations list → "+ Add a location" opens the same card as friends in `"place"` mode (`AddResidentForm.open("place")`: place photo from the front, name, and an "Add a flag" checkbox, auto-ticked with "Add its flag" for names with a known design). The place takes the next free district lot, facing the camera, shown as a `ConstructionModel` site with a "building 3D..." sign, and the camera flies there. Two ways to build it (checkbox on the card): **Quick build** (default) calls the relay's `/generate_place_recipe` with the photo + name; Claude (`claude-opus-5-5`, structured JSON output against `RECIPE_SCHEMA` in `relay/app.py`, effort medium, server-side refusal fallback) describes the place as a recipe of simple parts, and `RecipeModel.build` assembles it in code like the built-ins (~20 s, no GPU). The recipe is saved in world.json `places[].recipe` (no GLB) and rebuilt on load; `Location.set_recipe_model` sets footprint, hangout area, name tag and a height-based `view_distance`. If the player ticked the flag and the name has no known design, the recipe's `flag_colors` are used. **Detailed 3D** (checkbox "Detailed 3D scan"): the relay's `/generate_place` (TRELLIS `trellis-community/TRELLIS`: `/start_session` → `/preprocess_image` → `/generate_and_extract_glb`, simplify 0.97, 512 px texture) returns a static GLB; `Location.set_generated_model` turns it 180° (generated models face −Z), fits it in 9 m wide × 7 m tall, builds walls + footprint, grows the hangout area, adds the name sign and flag. Saved in world.json `"places"` + `user://places/<id>.glb`; restored before friends so saved homes resolve. Failed builds offer Retry/Remove; player-added places can be removed (two taps) and their friends wander anywhere again. Max 20 added places. Test mode: `RELAY_FAKE_PLACE_GLB=<glb>` makes `/generate_place` return that file.
- **Getting around:** a friend blocked by a building or another friend steps ~3 m sideways (alternating sides, up to 6 tries) and then resumes their target, so they can walk around buildings to a new home.
- **Flags & emblems:** when a location is a university, company, restaurant, etc. with a recognizable flag or symbol, include it (use judgement: skip it if the place has none worth showing). `flag.gd` builds a pole + cloth waving via a small shader; the artwork is drawn into an Image in code (no image assets). Designs: `"mcgill"` (red field, white shield, open book on a red chief, three martlets; stylized) or `{"colors": [field, accent]}` for a generic brand flag. Add new named designs in `Flag._draw_design`. McGill's flag flies from a pole on top of its dome.
- **Camera:** fixed angle (no orbit). One-finger drag pans (the ground point stays under the finger), a flick keeps gliding (FLING_FRICTION, MAX_FLING), pinch/wheel zooms smoothly (5-70 m) and the view tilts from -24 deg (close) to -58 deg (map view) as you zoom out. Picking a location glides to its front (`view_from`; `facing`/`pitch` args are ignored now) at `Location.view_distance` or a footprint fit. `CameraRig.velocity` feeds `FallingLeaves`: fast pans and flicks gust the leaves along and swirl them up, then they settle.
- **Physics layers:** buildings = layer 1, friends = layer 2 (`Resident.FRIEND_LAYER`). Tap/grab rays only check layer 2, so buildings never block picking a friend.
- **Menus:** one slide-up list panel (`_show_list`) serves Friends, Locations and the Home picker. Rows with `"friend"`/`"location"` get a picture from `thumbnailer.gd` (renders a copy of the model once in an offscreen SubViewport, cached).
- **Look & feel:** painted fall style matching the team's mascot art (oil-pastel goose, camera and map pin; our own art). `ui_style.gd` holds the palette (warm paper panels, terracotta borders, plum-brown text, burnt orange / teal / maple crimson / mustard accents, warm shadows; constant names CREAM/TAN/BROWN/LEAF/SKY/ORANGE are kept from the old palette) and builds the Theme: Grandstander font (`godot/fonts/Grandstander.ttf`, SIL OFL, license in `godot/fonts/Grandstander-OFL.txt`; weights 500/700 via FontVariation `wght` keyed with `name_to_tag`), pill buttons with soft shadows, speech-bubble panels. The McGill sign and all Label3D tags use `UiStyle.bold()`. World: hazy peach sky, golden grass, warm sun; trees come from `ModelKit.add_tree` (round crowns in orange/red/gold, every fifth an evergreen, chosen from position). `falling_leaves.gd` (CPUParticles3D, 44 billboard leaves, texture drawn in code) drifts leaves down around the camera rig's focus; keep it subtle. Controls under a CanvasLayer don't inherit the window theme, so `UiStyle.apply_to_layers(self)` gives each layer's top-level Controls the theme; build new UI before that call or set `.theme = UiStyle.theme()` yourself. Use `UiStyle.bubble()` / `pill()` / `title_sign()` for custom panels instead of hard-coded colours. Don't copy Nintendo assets or fonts.
- **Naming:** players only ever see "friends" (Add a friend, Your friends, Remove friend). In code they are still `Resident` / `residents`.
- **HUD layout** (positions inspired by mobile map games, with our own look): title + status top-left, round Pause top-right; bottom-left painted map-pin sticker Locations button (`icons/pin.png`, 108 px), bottom-centre Friends button (the goose mascot sticker `icons/goose.png`, 136 px, no disc; falls back to the drawn two-friends icon), bottom-right painted camera sticker to add a friend (`icons/camera.png`, 108 px, pulsing ring). Missing sticker files fall back to the drawn icons. A selected friend's bar has Wave / Dance / Home (+ Remove for saved friends). Panels (add form, friends list) hide the floating buttons and stop camera drags.

- **Residents:** outer `CharacterBody3D` (position, wandering, collision, `Label3D` name tag, selection ring) + inner `Avatar` (the loaded GLB). Only the avatar animates.
- **Animation:** all procedural, in `procedural_gait.gd`, on bones found from the skeleton's structure (see above). Each frame builds a pose (bone → skeleton-space rotation) for the walk and for the current action (`wave`: right arm up, forearm swinging; `dance`: knee bounce, torso sway/twist, alternating arm pumps, head bob) and slerps between them. Friends sometimes wave/dance on their own when idle; tapping a friend offers Wave/Dance buttons, and they turn to face the camera. Placeholders/unrecognized skeletons fall back to rocking (wave) or hop-and-spin (dance).
- **Friend behaviour:** when an idle pause ends there's a SOCIAL_CHANCE of a social moment picked by `Resident.ACTION_WEIGHTS`: wave at the viewer, wave at a nearby friend (they wave back), dance together with a free friend within 6 m (side-by-side **moonwalk** for the camera, or face each other for the **party** dance), solo dance, solo moonwalk. The Dance button does the same (together if someone's close). Moonwalk glides backwards (MOONWALK_SPEED). With a home, friends explore it via `Location.explore_point`: 6 sectors over the sides and front (the back is skipped, the camera can't see it), always the least-visited of their last 3.
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
- Quick build sends the (shrunk, metadata-free) photo of a *place* to the Anthropic API through the relay; it is not stored.

## Known limits

- ZeroGPU quota is per Hugging Face account. A free account runs out after a couple of generations per day; plan on HF PRO or a duplicated AniGen Space for demo day.
- The public AniGen Space can be slow or down; the relay retries connecting and returns friendly errors.
