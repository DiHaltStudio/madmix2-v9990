#!/usr/bin/env python3
"""Refresh the local latest-build delivery and checksums, using atomic files."""
from pathlib import Path
import hashlib,shutil
R=Path(__file__).resolve().parents[2];D=R/'release';D.mkdir(exist_ok=True)
files=[(R/'V9990/build/madmix2-v99990.rom','madmix2-v99990.rom')]
files += [(R/f'V9990/docs/manual/manual-{lang}.pdf',f'manual-{lang}.pdf') for lang in ('en','es')]
for src,name in files:
    if not src.is_file():
        if name.endswith('.rom'):raise FileNotFoundError(src)
        continue
    tmp=D/('.'+name+'.tmp');shutil.copyfile(src,tmp);tmp.replace(D/name)
lines=[]
for _,name in files:
    p=D/name
    if p.exists():lines.append(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {name}\n')
tmp=D/'.SHA256SUMS.tmp';tmp.write_text(''.join(lines));tmp.replace(D/'SHA256SUMS')
print('Updated release ROM, available manuals and SHA256SUMS')
