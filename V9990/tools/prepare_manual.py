#!/usr/bin/env python3
"""Rebuild manual artwork from checked emulator captures (no extraction at ROM build)."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
R=Path(__file__).resolve().parents[1];D=R/'docs';M=D/'manual'
# Portrait layout preserves the complete loading illustration and PC title.
canvas=Image.new('RGB',(840,1188),(8,8,20));draw=ImageDraw.Draw(canvas)
font=ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',30)
title=Image.open(D/'img/title.png').convert('RGB').crop((31,13,287,205)).resize((640,480),Image.Resampling.NEAREST)
canvas.paste(title,(100,30))
art=Image.open(R/'assets/opening/opening.jpeg').convert('RGB')
art.thumbnail((768,510),Image.Resampling.LANCZOS)
canvas.paste(art,((840-art.width)//2,530))
canvas.save(D/'img/manual-cover.png')
label_art=Image.new('RGB',(1800,860),(0,0,0))
title=Image.open(D/'img/title.png').convert('RGB').crop((31,13,287,205)).resize((880,660),Image.Resampling.NEAREST)
label_art.paste(title,(20,90))
art=Image.open(R/'assets/opening/opening.jpeg').convert('RGB')
art.thumbnail((880,660),Image.Resampling.LANCZOS)
label_art.paste(art,(900,90+(660-art.height)//2))
label_art.save(D/'img/label-art.png')
cfg={'cover':'docs/img/manual-cover.png','cover_shot':'docs/img/loading.png','title':'docs/img/title.png','montage':['docs/img/loading.png','docs/img/menu.png','docs/img/play.png'],'huds':[{'name':'hud','src':'docs/img/play.png','box':[31,13,287,205],'labels':[[1,167,18],[2,210,194,'b']]}],'label':{'lines':['MSX1 · 64 KB RAM','ASCII16 · 1 MiB'],'credit':'TOPO SOFT 1990 · V9990 PORT: DIHALT STUDIO 2026','art':'docs/img/label-art.png','fit':True}}
(M/'manual.json').write_text(json.dumps(cfg,indent=2)+'\n')
