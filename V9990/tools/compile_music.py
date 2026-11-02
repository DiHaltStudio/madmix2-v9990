#!/usr/bin/env python3
"""Original per-tick PSG trace -> standard AY VGM -> compact Z80 events.
VGM is editable authority after explicit --extract. Normal compilation reads it.
Only AY writes, PAL waits and end/loop are accepted; unknown commands fail.
"""
from pathlib import Path
import struct,sys,json
R=Path(__file__).resolve().parents[2]; B=R/'V9990/build'; A=R/'V9990/assets/music';A.mkdir(exist_ok=True)
p=A/'madmix2.vgm'
gain=json.loads((R/'V9990/src/audio-config.json').read_text())['music_volume_add']
assert type(gain) is int and 0<=gain<=15
if '--extract' in sys.argv:
    if p.exists():raise SystemExit('VGM already exists; refusing to overwrite')
    frames=(B/'music-frames.bin').read_bytes();start,end=map(int,(B/'music-loop.txt').read_text().split());assert len(frames)==end*11
    data=bytearray();prev=None;loop=0
    for n in range(end):
        if n==start:loop=len(data);prev=None
        row=frames[n*11:n*11+11]
        for reg,val in enumerate(row):
            if prev is None or prev[reg]!=val:data+=bytes((0xA0,reg,val))
        data.append(0x63);prev=row
    data.append(0x66);h=bytearray(256);h[:4]=b'Vgm '
    for off,value in ((4,len(h)+len(data)-4),(8,0x171),(0x18,end*882),(0x1c,256+loop-0x1c),(0x20,(end-start)*882),(0x24,50),(0x34,256-0x34),(0x74,1789772)):struct.pack_into('<I',h,off,value)
    h[0x79]=1;p.write_bytes(h+data)
v=p.read_bytes();assert v[:4]==b'Vgm ';pos=0x34+struct.unpack_from('<I',v,0x34)[0];loop=0x1c+struct.unpack_from('<I',v,0x1c)[0]
stream=bytearray();loopout=None;shadow=bytearray(11);decoded=bytearray();commands=0
while True:
    if pos==loop:loopout=len(stream)
    cmd=v[pos];pos+=1;commands+=1
    if cmd==0xA0:
        reg,val=v[pos:pos+2];pos+=2;assert reg<11
        # AY steps are logarithmic; retain zero silence and raise music only.
        if 8<=reg<=10 and val:val=min(15,val+gain)
        stream+=bytes((reg,val));shadow[reg]=val
    elif cmd==0x63:stream.append(0x80);decoded+=shadow
    elif cmd==0x66:stream.append(0xFF);break
    else:raise ValueError(f'Unsupported VGM opcode {cmd:02X}')
assert loopout is not None
(B/'music-events.bin').write_bytes(stream)
(B/'music-events.json').write_text(json.dumps(dict(bytes=len(stream),loop=loopout,ticks=len(decoded)//11,vgm_bytes=len(v),commands=commands),indent=2)+'\n')
if '--extract' in sys.argv:
    reference=bytearray((B/'music-frames.bin').read_bytes())
    for i in range(len(reference)):
        if i%11 in (8,9,10) and reference[i]:reference[i]=min(15,reference[i]+gain)
    assert decoded==reference
print('VGM:',len(v),'bytes; compiled events:',len(stream),'bytes; loop:',loopout)
