#!/usr/bin/env python3
"""Link privately owned source images and recordings outside public Git."""
import os
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=Path(os.environ.get('ORIGINAL_DIR',root.parent/'madmixgame2_v9990')).resolve()
required=[source/'MSX/build/game.bin',source/'MSX/build/loader.bin',source/'V9990/assets/music/madmix2.vgm',source/'V9990/assets/sfx/effect-00.vgm',source/'V9990/assets/opening/opening.jpeg']
missing=[str(x) for x in required if not x.is_file()]
if not list((source/'MSX/original').glob('*.cas')):missing.append(str(source/'MSX/original/*.cas'))
if missing:raise SystemExit('Private original resources missing. Set ORIGINAL_DIR to your original-game workspace containing MSX/build and V9990/assets/{music,sfx,opening}:\n'+'\n'.join(missing))
for target,origin in [(root/'MSX',source/'MSX')]+[(root/'V9990/assets'/name,source/'V9990/assets'/name) for name in ('music','sfx','opening')]:
 if target.is_symlink():
  if target.resolve()!=origin:raise SystemExit(f'Unexpected private link: {target}')
 elif target.exists():
  if target.name=='MSX' and target.is_dir() and not any(target.iterdir()):target.rmdir()
  else:raise SystemExit(f'Remove conflicting private resource path: {target}')
 if not target.exists():target.symlink_to(origin,target_is_directory=True)
