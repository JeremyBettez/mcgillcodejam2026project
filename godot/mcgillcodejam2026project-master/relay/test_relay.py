"""Call a running relay the same way the game will.

Usage: python relay/test_relay.py <relay url or Space id> <photo> <out dir>
Example: python relay/test_relay.py http://127.0.0.1:7860 photos/demo.jpg renders/relay
"""

import os
import shutil
import sys
import time

from gradio_client import Client, handle_file

src, photo, out_dir = sys.argv[1:4]
os.makedirs(out_dir, exist_ok=True)
start = time.time()
client = Client(src, verbose=False)
glb, cutout = client.predict(handle_file(photo), api_name='/generate')
shutil.copy(glb, os.path.join(out_dir, 'resident.glb'))
shutil.copy(cutout, os.path.join(out_dir, 'cutout.png'))
print(f'ok in {time.time() - start:.0f}s: {os.path.getsize(glb) // 1024} KB glb')
