#!/usr/bin/env python3
"""Build native P1 game from checked original images and editable art/maps."""
from pathlib import Path
import json, struct, subprocess, hashlib, os, re, xml.etree.ElementTree as ET
from PIL import Image
from palette64 import local_image
from compile_branding import fanfare_stream
from compile_opening import compile_opening
from compile_topo import compile_topo
from compile_ui import compile_ui
from compile_effects import compile_effects
from analyze_trace import load_sprites, sprite_pieces
R=Path(__file__).resolve().parents[2]; B=R/'V9990/build'; A=Path(os.environ.get('MADMIX_ASSET_ROOT',R/'V9990/assets'))
SJ=os.environ.get('SJASM','sjasm')
def asm(name):
    subprocess.run([SJ,str(R/'V9990/src'/f'{name}.asm'),str(B/f'{name}.bin')],cwd=R,check=True)
def main():
    contracts=json.loads((R/'V9990/src/patch-contracts.json').read_text())
    gameplay=json.loads((R/'V9990/src/gameplay-config.json').read_text())
    step_multiplier=gameplay['hard_world_step_multiplier']
    assert type(step_multiplier) is int and step_multiplier==2, "HARD doubles movement; select NORMAL at runtime for the original speed"
    B.mkdir(parents=True,exist_ok=True)
    (B/'gameplay-config.inc').write_text(f'WORLD_STEP_MULTIPLIER equ {step_multiplier}\nACTOR_DELTA_LIMIT equ {32*step_multiplier}\n')
    raw=(R/'MSX/build/game.bin').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==contracts['game_sha256'], 'Original game image changed; review patch contracts'
    loader=(R/'MSX/build/loader.bin').read_bytes()
    for a,expected in contracts['loader'].items():
        off=int(a,16)-0xC350;assert loader[off:off+len(bytes.fromhex(expected))]==bytes.fromhex(expected),a
    mem=bytearray(65536);mem[0x1060:0x1060+len(raw)]=raw
    for st in range(9):
        word=lambda a:int.from_bytes(mem[a:a+2],'little')
        resource=0x66F6+9*(st//3);desc=word(resource)+253*mem[0x43A3+st]
        groups=sum(mem[desc+a-0x3E8F] for a in (0x3E9C,0x3EBD,0x3EDE,0x3EFF,0x3F18,0x3F3B,0x3F46,0x3F67))+10
        assert 0xDCB9+groups*12<0xE000, 'Authored depth queue overlaps contacts helper'
    B.mkdir(parents=True,exist_ok=True)
    config=json.loads((A/'palette-config.json').read_text())
    colors=json.loads((A/'palettes.json').read_text())['banks']
    assert len(colors)==4 and all(len(b)==16 for b in colors)
    assert all(len(rgb)==3 and all(isinstance(v,int) and 0<=v<=31 for v in rgb) for bank in colors for rgb in bank)
    assert all(config[k] in range(4) for k in ('hud_bank','terrain_bank','sprite_bank'))
    assert config['stage_colors'] in ('original','fixed')
    (B/'port-art-config.inc').write_text(f"ART_PLANE_PALETTES equ {config['hud_bank']+4*config['terrain_bank']}\nART_SPRITE_ATTR equ {32+64*config['sprite_bank']}\nART_DETAIL_ATTR equ {32+64*config['terrain_bank']}\nART_STAGE_PALETTE equ {4*(16*config['terrain_bank']+1)}\nART_STAGE_ORIGINAL equ {int(config['stage_colors']=='original')}\n")
    def indexed(path,size,bank):
        im=local_image(path,bank,A);assert im.size==size,(path,size)
        return im
    uploads=[]
    # 8x8 patterns occupy physical 256-pixel-wide 4bpp pages.
    def pat8(tiles):
        data=bytearray(((len(tiles)+31)//32)*1024)
        for i,t in enumerate(tiles):
            for y in range(8):
                for x in range(0,8,2): data[(i//32)*1024+(i%32)*4+y*128+x//2]=(t[y*8+x]<<4)|t[y*8+x+1]
        return data
    patterns=[bytes(64),bytes([1])*64]
    # Editable font mask and gradients are authoritative, never re-extracted.
    fontpath=A/'font.png'
    im=local_image(fontpath,config['hud_bank'],A)
    # Font PNG is a mask: index 1 background, 2 foreground. Compile original
    # nine eight-line color gradients into plane-A's independent palette.
    styles=json.loads((A/'font-styles.json').read_text())['styles']
    assert len(styles)==9 and all(len(s)==8 and all(isinstance(v,int) and 0<=v<=255 for v in s) for s in styles)
    assert im.mode=='P' and im.size==(128,48) and set(im.tobytes())<={1,2}
    for style in range(9):
        for c in range(96):
            mask=im.crop(((c%16)*8,(c//16)*8,(c%16)*8+8,(c//16)*8+8)).tobytes()
            patterns.append(bytes((styles[style][y] & 15) if mask[y*8+x]==2 else (styles[style][y]>>4) for y in range(8) for x in range(8)))
    index={t:i for i,t in enumerate(patterns)}
    def tile_id(t):
        if t not in index:index[t]=len(patterns);patterns.append(t)
        return index[t]
    composition=ET.parse(A/'hud.tmx').getroot()
    assert (composition.get('width'),composition.get('height'))==('32','24')
    ref=composition.find('tileset');assert ref.get('firstgid')=='1'
    tsx=A/ref.get('source');ts=ET.parse(tsx).getroot()
    atlas=indexed(tsx.parent/ts.find('image').get('source'),(256,192),config['hud_bank'])
    gids=[int(v) for v in composition.find('layer/data').text.split(',') if v.strip()]
    assert len(gids)==768 and all(0<=v<=768 for v in gids)
    hud=Image.new('P',(256,192));hud.putpalette(atlas.getpalette())
    for i,gid in enumerate(gids):
        if gid:
            n=gid-1;x=(n%32)*8;y=(n//32)*8
            hud.paste(atlas.crop((x,y,x+8,y+8)),((i%32)*8,(i//32)*8))
    for y in range(192):
        for x in range(256):
            if not (32<=x<224 and 16<=y<160):assert hud.getpixel((x,y))!=0, 'HUD must remain opaque outside playfield'
    names=[]
    for y in range(24):
        for x in range(32):names.append(tile_id(hud.crop((x*8,y*8,x*8+8,y*8+8)).tobytes()))
    (B/'port-hud-names.bin').write_bytes(struct.pack('<768H',*names))
    im=indexed(A/'life.png',(24,24),config['hud_bank'])
    life=[tile_id(im.crop((x*8,y*8,x*8+8,y*8+8)).tobytes()) for y in range(3) for x in range(3)]
    (B/'port-life-names.bin').write_bytes(struct.pack('<9H',*life))
    # Native background art is always read from the editable TSX image.
    tiles=[]
    cpu_tiles=[]
    for fam in range(2):
        ts=ET.parse(A/f'tiles/family{fam}.tsx').getroot();im=indexed(A/'tiles'/ts.find('image').get('source'),(256,112),config['terrain_bank'])
        assert im.size==(256,112) and im.mode=='P'
        occupancy=(A/f'tiles/family{fam}-occupancy.dat').read_bytes()
        assert len(occupancy)==3584,'Occupancy must contain 56 original 32x16 masks'
        cpu_tiles.append(occupancy)
        for t in range(56):
            for sy in range(2):
                for sx in range(4):
                    x=(t%8)*32+sx*8;y=(t//8)*16+sy*8
                    tiles.append(im.crop((x,y,x+8,y+8)).tobytes())
    assert len(pat8(patterns))<=0x10000
    uploads += [(0,pat8(patterns)),(0x40000,pat8(tiles)),(0x48000,pat8(tiles)),(0x72000,pat8(tiles))]
    # Master sprite atlas. Three identities per pose preserve original reflected
    # four-pixel alignment; runtime HUD clips the complete hardware pieces.
    sprites=load_sprites(A); unique=[];lookup={};descs=bytearray();offsets=[]
    for variant in range(3):
        for sid in range(105):
            x=68 if variant==1 else 64
            pieces=sprite_pieces(dict(a=sid|(128 if variant else 0),d=32,e=x),sprites)
            offsets.append(len(descs));descs.append(len(pieces))
            for p in pieces:
                pix=bytes(p['pixels'])
                if pix not in lookup:lookup[pix]=len(unique);unique.append(pix)
                n=lookup[pix]
                descs += struct.pack('<bbHHB',p['x']-x,p['y']-32,(n%16)*16,512+(n//16)*16,32+64*p['bank'])
    master=bytearray(((len(unique)+15)//16)*2048)
    for i,t in enumerate(unique):
        for y in range(16):
            for x in range(0,16,2): master[(i//16)*2048+(i%16)*8+y*128+x//2]=(t[y*16+x]<<4)|t[y*16+x+1]
    assert len(master)<0x10000
    uploads.append((0x10000,master))
    # Shared one-pixel black detail pattern, reserved slot126 in each cache.
    uploads += [(0x33870,b'\x10'),(0x3B870,b'\x10')]
    details=bytearray()
    for i in range(60):
        x,y=mem[0x42E1+2*i:0x42E3+2*i];mask,pixel=mem[0x60A0+2*(x&7):0x60A2+2*(x&7)]
        assert pixel and pixel&(pixel-1)==0
        details+=bytes((x&248,y,mask,(x&248)+7-(pixel.bit_length()-1)))
    (B/'port-detail-points.bin').write_bytes(details)
    (B/'port-pose-data.bin').write_bytes(descs)
    (B/'port-pose-offsets.bin').write_bytes(b''.join(struct.pack('<H',x) for x in offsets))
    # Store full editable maps in VRAM as non-displayed data. Runtime loads the
    # selected 3584-byte bank into original A900 collision/game map RAM.
    maps=bytearray(9*4096)
    for i in range(9):
        m=ET.parse(A/f'maps/stage{i+1}.tmx').getroot();data=m.find('layer/data');assert data.get('encoding')=='csv'
        cells=[int(v.strip())-1 for v in data.text.split(',') if v.strip()]
        assert len(cells)==64*int(m.get('height')) and len(cells)<=3584 and all(0<=v<56 for v in cells)
        maps[i*4096:i*4096+len(cells)]=bytes(cells)
    uploads.append((0x20000,maps))
    pal=bytes(c for bank in json.loads((A/'palettes.json').read_text())['banks'] for rgb in bank for c in rgb)
    (B/'port-palette.bin').write_bytes(pal)
    (B/'port-tms-palette.bin').write_bytes(pal[48:96])
    # Independent editable PC title: plane B patterns above terrain, names at7E000.
    title=Image.open(A/'screens/title.png');assert title.mode=='P' and title.size==(256,192)
    assert max(title.tobytes())<16
    tp=[bytes(64)];tn=bytearray(struct.pack("<4096H",*([2048]*4096)))
    for y in range(24):
        for x in range(32):
            t=title.crop((x*8,y*8,x*8+8,y*8+8)).tobytes()
            if t not in tp:tp.append(t)
            struct.pack_into('<H',tn,(y*64+x)*2,2048+tp.index(t))
    uploads.append((0x50000,pat8(tp)))
    (B/'title-names.bin').write_bytes(b''.join(tn[y*128:y*128+64] for y in range(24)))
    loading=Image.open(A/'screens/loading.png');assert loading.mode=='P' and loading.size==(256,192)
    assert set(loading.tobytes())<={0,15}
    lp=[bytes(64)];ln=bytearray(struct.pack('<4096H',*([3072]*4096)))
    for y in range(24):
        for x in range(32):
            t=loading.crop((x*8,y*8,x*8+8,y*8+8)).tobytes()
            if t not in lp:lp.append(t)
            struct.pack_into('<H',ln,(y*64+x)*2,3072+lp.index(t))
    assert len(pat8(lp))<=0x8000
    uploads.extend([(0x58000,pat8(lp)),(0x7E000,ln)])
    (B/'title-palette.bin').write_bytes(bytes(round(v*31/255) for v in title.getpalette()[:48]))
    (B/'title-game-palette.bin').write_bytes(pal[144:192])
    uploads.extend(compile_ui(A,B,config))
    uploads.append((0x47FE0,bytes(32)))  # immutable blank pattern1023
    topo_tiles,topo_stream,topo_frames=compile_topo(A)
    assert 0x60000+len(pat8(topo_tiles))<=0x72000, "Topo atlas overlaps immutable terrain master"
    uploads.append((0x60000,pat8(topo_tiles)))
    # Game plus original loader sequence occupy banks 0..7. Preload assets using
    # a temporary page-3 routine while page 1 still contains the cartridge.
    banks=[];inc=[];upload_banks={}
    for address,blob in uploads:
        for off in range(0,len(blob),16384):
            chunk=blob[off:off+16384];padded=bytes(chunk).ljust(16384,b'\0')
            if padded not in upload_banks:
                upload_banks[padded]=8+len(banks);banks.append(padded)
            bank=upload_banks[padded];addr=address+off
            inc += [f'    ld a,{bank}','    ld ($6000),a',f'    ld a,{addr>>16}',f'    ld de,${addr&65535:04X}','    call set_write','    ld hl,$4000',f'    ld de,{len(chunk)}','    call upload']
    (B/'port-uploads.inc').write_text('\n'.join(inc)+'\n')
    subprocess.run(['python3',str(R/'V9990/tools/compile_music.py')],check=True)
    music=(B/'music-events.bin').read_bytes(); music_bank=8+len(banks)
    meta=json.loads((B/'music-events.json').read_text()); loop=meta['loop']
    (B/'port-music.inc').write_text(f'MUSIC_BANK equ {music_bank}\nMUSIC_LOOP_BANK equ {music_bank+loop//16384}\nMUSIC_LOOP_PTR equ {0x4000+loop%16384}\n')
    for off in range(0,len(music),16384):banks.append(music[off:off+16384].ljust(16384,b'\xff'))
    (B/'topo-config.inc').write_text(f'TOPO_BANK equ {8+len(banks)}\nTOPO_FRAMES equ {len(topo_frames)}\n')
    for off in range(0,len(topo_stream),16384):banks.append(topo_stream[off:off+16384].ljust(16384,b'\xff'))
    (B/'topo-build.json').write_text(json.dumps({'frames':len(topo_frames),'patterns':len(topo_tiles),'stream_bytes':len(topo_stream)},indent=2)+'\n')
    # Original Spy2 DiHalt logo, byte-exact RGB332; no new quantization.
    logo=Image.open(A/'branding/dihalt_logo-b1.png').convert('RGB')
    assert logo.size==(256,212)
    logo_raw=bytearray()
    for r,g,b in logo.getdata():
        code=(((g*7+127)//255)<<5)|(((r*7+127)//255)<<2)|((b*3+127)//255)
        assert (r,g,b)==(((code>>2)&7)*255//7,((code>>5)&7)*255//7,(code&3)*255//3)
        logo_raw.append(code)
    inc=[]
    for off in range(0,len(logo_raw),16384):
        chunk=logo_raw[off:off+16384];bank=8+len(banks);banks.append(chunk.ljust(16384,b'\0'))
        inc += [f'    ld a,{bank}','    ld ($6000),a','    xor a',f'    ld de,{off}','    call set_write','    ld hl,$4000',f'    ld de,{len(chunk)}','    call upload']
    fanfare,frames=fanfare_stream(A/'branding/dihalt_fanfare.vgm')
    (B/'branding-fanfare.bin').write_bytes(fanfare)
    (B/'branding-uploads.inc').write_text(f'BRANDING_FRAMES equ {frames+50}\n'+'\n'.join(inc)+'\n')
    (B/'branding.json').write_text(json.dumps({'music_frames':frames,'total_frames':frames+50,'hz':50,'source':'Spy vs Spy2 V9990 opening'},indent=2)+'\n')
    opening=compile_opening(A,B)
    inc=[]
    for off in range(0,len(opening),16384):
        chunk=opening[off:off+16384];bank=8+len(banks);banks.append(chunk.ljust(16384,b'\0'))
        inc += [f'    ld a,{bank}','    ld ($6000),a',f'    ld a,{off>>16}',f'    ld de,{off&65535}','    call set_write','    ld hl,$4000',f'    ld de,{len(chunk)}','    call upload']
    (B/'opening-uploads.inc').write_text('\n'.join(inc)+'\n')
    controls=(R/'V9990/src/port_presentation.asm').read_text().split('control:\n',1)[1].split('title_show:',1)[0]
    (B/'opening-control.inc').write_text('control:\n'+controls.replace('control_release:\n','control_release:\n    call opening_secret\n'))
    (B/'smooth-config.inc').write_text(f'SMOOTH_BANK equ {8+len(banks)}\n')
    sfx_pools=compile_effects()
    asm('port_sfx')
    for name in ('port_topo','port_ui','port_menu','port_presentation','port_slots','port_bridge','port_trampoline','port_restore','port_runtime','port_preload','port_boot'):
        asm(name)
        if name=='port_ui':
            listing=(B/'port_ui.lst').read_text()
            addr=int(re.search(r'00:0000([0-9A-F]{4})\s+(?:X\s+)?ui_credits\s*$',listing,re.M)[1],16)
            (B/'ui-api.inc').write_text(f'UI_BYTES equ {len((B/"port_ui.bin").read_bytes())}\nUI_CREDITS equ ${addr:04X}\n')
            audio_api=[]
            for label in ('music_active','music_bank','music_ptr','music_shadow'):
                address=int(re.search(r'00:0000([0-9A-F]{4})\s+(?:X\s+)?shared_'+label+r'\s*$',listing,re.M)[1],16)
                audio_api.append(f'{label} equ ${address:04X}')
            (B/'ui-audio-api.inc').write_text('\n'.join(audio_api)+'\n')
        if name=='port_runtime':
            listing=(B/'port_runtime.lst').read_text();api=[]
            for label in ('reg_write','set_write','sprite_page','scroll_x','scroll_y','piece_count','audio_clock','vblank','command','pattern_slot','wait_command','clear_ui','display_off','display_on'):
                addr=int(re.search(r'00:0000([0-9A-F]{4})\s+(?:X\s+)?'+label+r'\s*$',listing,re.M)[1],16)
                api.append(f'{label} equ ${addr:04X}')
            (B/'smooth-api.inc').write_text('\n'.join(api)+'\n')
            asm('port_smooth')
            helper_listing=(B/'port_smooth.lst').read_text()
            gen=int(re.search(r'00:0000([0-9A-F]{4})\s+(?:X\s+)?generation\s*$',helper_listing,re.M)[1],16)
            contact_api='    include "../build/smooth-api.inc"\n'+f'GENERATION equ ${gen:04X}\n'
            for label in ('offset_x','offset_y','phase','hardware_count','front_count'):
                addr=int(re.search(r'00:0000([0-9A-F]{4})\s+(?:X\s+)?'+label+r'\s*$',helper_listing,re.M)[1],16)
                contact_api+=(f'SCROLL_PHASE equ ${addr:04X}\n' if label=='phase' else (f'GPU_{label.upper()} equ ${addr:04X}\n' if label.endswith('_count') else f'SCROLL_HALF_{label[-1].upper()} equ ${addr:04X}\n'))
            mid=int(re.search(r'00:0000([0-9A-F]{4})\s+(?:X\s+)?compose_sat\s*$',helper_listing,re.M)[1],16)
            contact_api+=f'STAGE_MID_SAT equ ${mid:04X}\n'
            (B/'contacts-api.inc').write_text(contact_api)
            asm('port_contacts')
            banks.append(((B/'port_smooth.bin').read_bytes()+(B/'port_contacts.bin').read_bytes()+(B/'port_sfx.bin').read_bytes()).ljust(16384,b'\xff'))
    # Fixed jump table makes patch sites reviewable and independent of code size.
    game=bytearray(raw)
    def patch(addr,expected,new):
        assert expected==bytes.fromhex(contracts['game'][f'{addr:04X}']),hex(addr)
        off=addr-0x1060;assert game[off:off+len(expected)]==expected,hex(addr);game[off:off+len(new)]=new
    hooks=[(0x1060,0),(0x5C7D,1),(0x55A1,2),(0x5B7D,3),(0x58DA,4),(0x58E8,5),(0x5B02,6),(0x5B3F,7),(0x416D,8),(0x41D7,9),(0x9DD4,10),(0x9DEF,11),(0xA201,13),(0x6062,14),(0x578C,15)]
    for addr,index in hooks:patch(addr,mem[addr:addr+3],b'\xc3'+struct.pack('<H',0x1100+3*index))
    patch(0x38CD,bytes.fromhex('cd593b'),b'\xcd'+struct.pack('<H',0x1136))
    for addr,expected,target,opcode in (
        (0x6471,'21b83f',0x069B,0xC3),
        (0x64B7,'2ac864',0x069E,0xC3),
        (0x64BC,'712373',0x06A1,0xC3),
        (0x64AF,'edb8e1',0x06A4,0xC3),
        (0x64F5,'c4a155',0x06A7,0xC4),
        (0x3886,'cde438',0x06AA,0xCD),
        (0x43C7,'cd0e58',0x06AD,0xC3),
        (0x384B,'cd2042',0x06B0,0xCD),
        (0x3BCE,'cda155',0x06B3,0xCD),
    ):patch(addr,bytes.fromhex(expected),bytes([opcode])+struct.pack('<H',target))

    for addr,target in ((0x398D,0xE000),(0x3997,0xE003),(0x4D8F,0x06BF),(0x4E08,0x06BF),(0x4BC7,0xE030),(0x4D04,0xE033),(0x5131,0xE039)):
        patch(addr,mem[addr:addr+3],b'\xcd'+struct.pack('<H',target))
    for addr,target in ((0x3A73,0x06C2),(0x4DE5,0xE006),(0x4D69,0xE009),(0x5272,0x06CB),(0x4F44,0xE00C),(0x4E9F,0xE00F),(0x556A,0xE012),(0x412B,0xE021)):
        patch(addr,mem[addr:addr+3],b'\xc3'+struct.pack('<H',target))
    patch(0x3855,bytes.fromhex('cddea8'),bytes(3))  # retired mirror table overlaps terrain alias caches
    patch(0x5335,bytes.fromhex('ed5b933eed4b953e3e00'),bytes.fromhex('cd24e0')+bytes(7))
    patch(0x37E9,bytes.fromhex('cde861'),bytes(3))
    patch(0x43C4,bytes.fromhex('c3c743'),b'\xc3'+struct.pack('<H',0x1133))
    patch(0x3808,bytes.fromhex('dd215067'),b'\xc3'+struct.pack('<H',0x1130)+b'\x00')
    patch(0x557F,bytes.fromhex('cd239e'),b'\xcd'+struct.pack('<H',0x1100+3*12))
    for addr in (0x3838,0x546F):patch(addr,mem[addr:addr+3],bytes(3))
    patch(0xB6DF,bytes.fromhex('cdef9d'),bytes.fromhex('fb0000'))
    patch(0x53CC,bytes.fromhex('c3d253'),bytes.fromhex('c336e0'))
    patch(0x4911,bytes.fromhex('cdd253'),bytes.fromhex('cd36e0'))
    patch(0x9E04,bytes.fromhex('f5d511'),bytes.fromhex('c303ce'))
    patch(0x9E23,bytes.fromhex('f50603'),bytes.fromhex('c300ce'))
    for (start,end),data in sfx_pools:
        off=start-0x1060
        assert game[off:off+len(data)]==raw[off:off+len(data)], 'SFX storage overlaps another patch'
        assert len(data)==end-start
        game[off:off+len(data)]=data
    for addr in (0x6711,0xA8DE):patch(addr,mem[addr:addr+1],b'\xc9')
    for addr,data in zip((0x67CB,0x800B),cpu_tiles):game[addr-0x1060:addr-0x1060+len(data)]=data
    runtime=(B/'port_runtime.bin').read_bytes();assert len(runtime)<=0x3765-0x1100
    game[0x1100-0x1060:0x1100-0x1060+len(runtime)]=runtime
    rom=bytearray((B/'port_boot.bin').read_bytes());assert len(rom)==16384
    for name in ('opening','intro','stage'):
        blob=bytearray((R/f'MSX/build/{name}.bin').read_bytes())
        expected_hash={'opening':'609c540e82fe09bae034e481e94ae4519b782cb1164e32daaaa8e98db051750d','intro':'467b04f89c3adbe13cc9cbca3e72d2b35a76d518599ec1147469265cab3e092a','stage':'8bc0336ef8f7a72b655089abcd06555af5cbd2e2ea083abc885fd9c111315f36'}[name]
        assert hashlib.sha256(blob).hexdigest()==expected_hash, name+' presentation patch source changed'
        base=0x1000 if name=='stage' else 0x88B8
        def edit(addr,old,new):
            off=addr-base;assert blob[off:off+len(old)]==old,(name,hex(addr))
            assert len(old)==len(new);blob[off:off+len(old)]=new
        if name=='intro':blob=bytearray((B/'port_topo.bin').read_bytes()).ljust(len(blob),b'\0')
        if name=='opening':
            edit(0xA581,bytes.fromhex('f32100'),bytes.fromhex('c38006'))
            edit(0xA596,bytes.fromhex('c3b8a3'),bytes.fromhex('c38006'))
        if name=='stage':
            menu=(B/'port_menu.bin').read_bytes();assert len(menu)<=0x2F1D-0x2B6A
            ui=(B/'port_ui.bin').read_bytes();assert len(ui)<=2048
            blob[0x2B6A-0x1000:0x2F1D-0x1000]=menu.ljust(0x2F1D-0x2B6A,b'\0')
            blob[0x1800-0x1000:0x1800-0x1000+len(ui)]=ui
            edit(0x1060,bytes.fromhex('c3c216'),bytes.fromhex('c36a2b'))
            edit(0x1692,bytes.fromhex('f3f5db'),bytes.fromhex('c30ce8'))
        rom+=blob.ljust(16384,b'\xff')
    rom+=game[:20000].ljust(32768,b'\xff')+game[20000:].ljust(32768,b'\xff')+b''.join(banks)
    size=1
    while size<len(rom):size*=2
    rom=rom.ljust(size,b'\xff')
    rom_tmp=B/'madmix2-v99990.rom.tmp'
    rom_tmp.write_bytes(rom)
    rom_tmp.replace(B/'madmix2-v99990.rom')
    (B/'port-build.json').write_text(json.dumps(dict(bytes=len(rom),resident_bytes=len(runtime),master_patterns=len(unique),maps=9,hooks=[hex(a) for a,i in hooks]),indent=2)+'\n')
    print('Native P1 ROM:',len(rom),'bytes; runtime',len(runtime),'bytes')
if __name__=='__main__':main()
