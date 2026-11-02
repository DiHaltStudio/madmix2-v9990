#!/usr/bin/env python3
"""Measure original painter calls as candidate P1 hardware pieces, not VDP FPS."""
from pathlib import Path
import csv,json,statistics
from PIL import Image
from palette64 import local_image,sprite_images
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'V9990/build';ASSETS=ROOT/'V9990/assets'

def load_sprites(asset_root=ASSETS):
    config_path=asset_root/'palette-config.json'
    bank=json.loads(config_path.read_text())['sprite_bank'] if config_path.exists() else 0
    palette=json.loads((asset_root/'palettes.json').read_text())['banks'][bank]
    preview=[round(c*255/31) for rgb in palette for c in rgb]
    images=[]
    sheet_meta=asset_root/'sprites/sprites.json'
    if sheet_meta.exists():return sprite_images(asset_root)
    manifest=json.loads((asset_root/'original-extraction.json').read_text())
    sources=[(r,Image.open(asset_root/r['file']).copy()) for r in manifest['sprites']]
    for row,im in sources:
        assert im.mode=='P' and im.size==(row['width'],row['height']),row
        assert max(im.tobytes())<16,row
        assert im.getpalette()[:48]==preview, 'PNG palette must agree with palettes.json; run palettes-sync'
        images.append(im)
    return images

PIECE_CACHE={}

def sprite_pieces(row,sprites,tight=True,clip=True):
    key=(int(row["a"]),int(row["d"]),int(row["e"]),tight,clip)
    if key in PIECE_CACHE:return PIECE_CACHE[key]
    if int(row['d'])==144:return []  # original consumed-component marker
    sid=int(row['a'])
    if sid==255:return []
    sid0=sid&127
    assert sid0<len(sprites),sid
    im=sprites[sid0]
    if sid&128:im=im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    x=int(row['e'])&252;y=int(row['d'])
    if sid&128:
        x=((int(row['e'])-4)&255)&252
        # Original reflected blit subtracts four pixels; its shifted path writes
        # only three bytes, dropping the leftmost four reflected pixels.
        if not (int(row['e'])&4):
            im=im.crop((4,0,im.width,im.height));x+=4
    if y>=(224 if clip else 208):y-=256
    if tight:
        bounds=im.getbbox()
        if not bounds:return []
        x+=bounds[0];y+=bounds[1];im=im.crop(bounds)
    pieces=[]
    for py in range(0,im.height,16):
        for px in range(0,im.width,16):
            tile=Image.new('P',(16,16))
            for dy in range(16):
                for dx in range(16):
                    xx=x+px+dx;yy=y+py+dy
                    if (not clip or (32<=xx<224 and 0<=yy<144)) and px+dx<im.width and py+dy<im.height:
                        tile.putpixel((dx,dy),im.getpixel((px+dx,py+dy)))
            if tile.getbbox():pieces.append(dict(x=x+px,y=y+py,pixels=list(tile.tobytes()),sprite=sid,bank=sprites[sid0].info.get('palette_bank',0)))
    PIECE_CACHE[key]=pieces
    return pieces

def main():
    sprites=load_sprites();reports=[];worst=None;allpatterns=set()
    for im in sprites:
        for flip in (False,True):
            source=im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if flip else im
            for y in range(0,im.height,16):
                for x in range(0,24,16):
                    p=Image.new('P',(16,16));p.paste(source.crop((x,y,min(x+16,24),min(y+16,im.height))),(0,0))
                    if p.getbbox():allpatterns.add(p.tobytes())
    trimmed=set()
    for sid in range(105):
        for flip in (0,128):
            for x in (64,68):
                trimmed.update(bytes(p['pixels']) for p in sprite_pieces(dict(a=sid|flip,d=32,e=x),sprites))
    for name in ('phase12','phase9'):
        frames={};bi=fi=0
        for row in csv.DictReader((BUILD/f'{name}.csv').open()):
            n=int(row['frame']);f=frames.setdefault(n,dict(frame=n,sprites=[],pieces=[],fixed_pieces=[],events={},stage=int(row['stage'])))
            event=row['event'];f['events'][event]=float(row['time'])
            if event=='sprite':f['sprites'].append(row);f['pieces']+=sprite_pieces(row,sprites);f['fixed_pieces']+=sprite_pieces(row,sprites,False)
            if event=='background':f['background_index']=bi;bi+=1
            if event=='composed':f['final_index']=fi;fi+=1
        valid=[f for n,f in frames.items() if n>=0 and all(k in f['events'] for k in ('start','background','composed','uploaded'))]
        for f in valid:
            loads=[sum(p['y']<=y<p['y']+16 for p in f['pieces']) for y in range(144)]
            f['fixed_peak_line']=max(sum(p['y']<=y<p['y']+16 for p in f['fixed_pieces']) for y in range(144));f['peak_line']=max(loads);f['pieces_count']=len(f['pieces']);f['line_loads']=loads
            f['unique_patterns']=len({bytes(p['pixels']) for p in f['pieces']})
            if worst is None or (f['peak_line'],f['pieces_count'])>(worst['peak_line'],worst['pieces_count']):worst=dict(f,trace=name)
        rep=dict(trace=name,frames=len(valid),peak_pieces=max(f['pieces_count'] for f in valid),peak_line=max(f['peak_line'] for f in valid),overflow_frames=sum(f['peak_line']>16 or f['pieces_count']>125 for f in valid),fixed_grid_peak_line=max(f['fixed_peak_line'] for f in valid),fixed_grid_overflow_frames=sum(f['fixed_peak_line']>16 for f in valid),peak_unique_patterns=max(f['unique_patterns'] for f in valid),
                 median_original_frame_ms=1000*statistics.median(f['events']['uploaded']-f['events']['start'] for f in valid),
                 median_original_background_ms=1000*statistics.median(f['events']['background']-f['events']['start'] for f in valid),
                 median_original_upload_ms=1000*statistics.median(f['events']['uploaded']-f['events']['composed'] for f in valid))
        reports.append(rep)
    (BUILD/'worst-frame.json').write_text(json.dumps(worst)+'\n')
    report=dict(recordings=reports,unique_unclipped_sprite_patterns=len(allpatterns),unique_trimmed_patterns_with_reflected_alignments=len(trimmed),sprite_limit=125,scanline_limit=16,pattern_slots_per_base=256,
                assumptions=['Transparent bounding box trimmed per pose before 16x16 splitting; fixed-grid results also reported','Mirroring and clipping generate distinct pattern identities','Viewport X=32..223, Y=0..143; original X quantized to 4 pixels','Lower-bound transfer cost excludes pattern-cache misses, map streaming and IRQ work','OMR sample does not establish worst case for all nine stages'])
    (BUILD/'mode-evaluation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
