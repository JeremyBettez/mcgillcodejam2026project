---
title: Photo Town Relay
emoji: 🏘️
colorFrom: red
colorTo: yellow
sdk: gradio
sdk_version: 6.31.0
python_version: '3.10'
app_file: app.py
pinned: false
---

# Photo Town relay

The Photo Town game sends a full-body photo here. This Space calls the public
[AniGen Space](https://huggingface.co/spaces/VAST-AI/AniGen), which builds the
3D model, and returns a low-poly rigged `.glb` (about 2.5k triangles, 22 bones,
512 px texture) plus the background-removed cut-out.

## API

`/generate`: input is an image, outputs are `[resident.glb, cutout.png]`.

## Setup

- Hardware: free CPU basic. The GPU work runs on AniGen.
- Secret `HF_TOKEN`: a Hugging Face Read token. AniGen's ZeroGPU time is charged to that account.
- Optional variable `ANIGEN_SPACE`: point this at a duplicate of AniGen to use your own GPU.

## Run locally

```sh
pip install gradio==6.31.0
HF_TOKEN=hf_... python app.py
```
