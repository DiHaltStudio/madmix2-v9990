"""Shared RGB5 master, identical 64-color PNG tables and global bank indices."""
from pathlib import Path
import argparse,json,os
from PIL import Image
A=Path(os.environ.get('MADMIX_ASSET_ROOT',Path(__file__).resolve().parents[1]/'assets'))
FILES={'tiles/family0.png':'terrain_bank','tiles/family1.png':'terrain_bank','sprites/sprites.png':'sprite_bank','hud.png':'hud_bank','life.png':'hud_bank','font.png':'hud_bank','font-large.png':'hud_bank'}
ALPHA=bytes(0 if i%16==0 else 255 for i in range(256))
def table(root=A):
    banks=json.loads((root/'palettes.json').read_text())['banks']
    assert len(banks)==4 and all(len(b)==16 for b in banks)
    assert all(len(c)==3 and all(type(v)==int and 0<=v<=31 for v in c) for b in banks for c in b)
    return [round(v*255/31) for b in banks for c in b for v in c]
def local_image(path,bank,root=A):
    im=Image.open(path);assert im.mode=='P',f'{path}: indexed PNG required'
    assert im.getpalette()[:192]==table(root),f'{path}: palette differs; run make palette-sync MASTER=path/to/edited.png'
    pixels=im.tobytes()
    assert all(v<64 and (v%16==0 or v//16==bank) for v in pixels),f'{path}: opaque pixels must use bank {bank}'
    out=Image.frombytes('P',im.size,bytes(v&15 for v in pixels));out.putpalette(table(root)[bank*48:bank*48+48]+[0]*720)
    out.info['transparency']=0
    return out

def sprite_images(root=A):
    meta=json.loads((root/'sprites/sprites.json').read_text())
    sheet=Image.open(root/'sprites'/meta['image']);assert sheet.mode=='P' and sheet.size==(256,448)
    assert sheet.getpalette()[:192]==table(root),'Sprite palette differs; synchronize MASTER first'
    assert [r['id'] for r in meta['poses']]==list(range(105))
    cfg=json.loads((root/'palette-config.json').read_text());images=[]
    for row in meta['poses']:
        bank=row.get('palette_bank',cfg['sprite_bank']);assert bank in range(4)
        im=sheet.crop((row['x'],row['y'],row['x']+row['width'],row['y']+row['height']))
        assert all(v<64 and (v%16==0 or v//16==bank) for v in im.tobytes()),f"Pose {row['id']}: pixels must use bank {bank} from sprites.json"
        out=Image.frombytes('P',im.size,bytes(v&15 for v in im.tobytes()));out.putpalette(table(root)[bank*48:bank*48+48]+[0]*720)
        out.info['transparency']=0;out.info['palette_bank']=bank;images.append(out)
    return images

def sync(root=A,master=None):
    if master:
        p=Path(master)
        if not p.is_file():
            matches=[root/n for n in FILES if n==master or Path(n).name==master]
            assert len(matches)==1,f'Unknown master {master}'
            p=matches[0]
        im=Image.open(p);assert im.mode=='P' and len(im.getpalette())>=192
        rgb=im.getpalette()[:192];banks=[[[round(v*31/255) for v in rgb[i:i+3]] for i in range(b*48,b*48+48,3)] for b in range(4)]
        j=json.loads((root/'palettes.json').read_text());j['banks']=banks;(root/'palettes.json').write_text(json.dumps(j,indent=2)+'\n')
    colors=table(root)+[0]*576
    for name in FILES:
        p=root/name;im=Image.open(p);assert im.mode=='P';before=im.tobytes();im.putpalette(colors);im.save(p,transparency=ALPHA)
        assert Image.open(p).tobytes()==before

def main():
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['sync','check']);ap.add_argument('--master');args=ap.parse_args()
    if args.action=='sync':sync(master=args.master)
    cfg=json.loads((A/'palette-config.json').read_text())
    for name,key in FILES.items():
        if key=='sprite_bank':sprite_images(A)
        else:local_image(A/name,cfg[key])
    print('PASS: six editable PNGs share 64 colors; terrain/sprite/HUD bank indices valid')
if __name__=='__main__':main()
