#!/usr/bin/env python3
"""Compile editable AY VGMs into resident, bounded-cost SFX runs.
The retired original PSG interpreter/music bytes become read-only run storage;
no effect tick maps ROM or executes original note/envelope bytecode.
"""
from pathlib import Path
import json,struct
R=Path(__file__).resolve().parents[2]; B=R/'V9990/build'; A=R/'V9990/assets/sfx'
POOLS=((0x9E23+3,0xA201),(0xA310,0xA777)) # retain9E23 detour,A201,shadow,toggle,queue

def frames(path):
 v=path.read_bytes();assert v[:4]==b'Vgm '
 pos=0x34+struct.unpack_from('<I',v,0x34)[0];off=struct.unpack_from('<I',v,0x1c)[0];loop=off+0x1c if off else -1
 rows=[];looprow=-1;shadow=bytearray(11)
 while True:
  if pos==loop:looprow=len(rows)
  cmd=v[pos];pos+=1
  if cmd==0xA0:
   reg,val=v[pos:pos+2];pos+=2;assert reg in (0,1,6,7,8);shadow[reg]=val
  elif cmd==0x63:rows.append(bytes(shadow))
  elif cmd==0x66:break
  else:raise ValueError(f'{path}: unsupported opcode {cmd:02X}')
 assert rows and max(r[1] for r in rows)<16 and max(r[8] for r in rows)<16
 return rows,looprow

def compile_effects():
 raw=(R/'MSX/build/game.bin').read_bytes();records=[];effects=[];fixups=[];notes={}
 for effect in range(15):
  rows,loop=frames(A/f'effect-{effect:02d}.vgm');runs=[];previous=None;looprun=None
  narrow=effect==13
  if narrow:
   assert all(r[7]&9==8 for r in rows)
   groups=[]
   for i,r in enumerate(rows):
    tone=r[:2]
    if not groups or groups[-1][0]!=tone or i==loop or len(groups[-1][1])==255:
     if i==loop:looprun=len(groups)
     groups.append((tone,bytearray()))
    groups[-1][1].append(r[8])
   for tone,volumes in groups:
    key=(tone,bytes(volumes))
    if key not in notes:notes[key]=len(notes)+1
    assert len(notes)<256,'Too many distinct VGM tone/volume runs'
    runs.append(bytearray((notes[key],)))
  else:
   for i,r in enumerate(rows):
    row=bytes((r[0],r[1]|r[8]<<4,r[6],r[7]&9))
    if row!=previous or i==loop or runs[-1][0]==255:
     if i==loop:looprun=len(runs)
     runs.append(bytearray((0,))+row)
    runs[-1][0]+=1;previous=row
  start=len(records);records.extend(runs);end=len(records);records.append(bytearray(3))
  if looprun is not None:fixups.append((end,1,start+looprun))
  src=struct.unpack_from('<H',raw,0xA7B1+3*effect-0x1060)[0]
  effects.append(dict(id=effect,source=src,record=start,narrow=narrow,ticks=len(rows),loop=loop))
 table=len(records);records.append(bytearray(4*len(notes)))
 profiles={}
 for (tone,volumes),token in notes.items():
  if volumes not in profiles:
   profiles[volumes]=len(records);records.append(bytearray((len(volumes),))+volumes)
  off=4*(token-1);records[table][off:off+2]=tone;fixups.append((table,off+2,profiles[volumes]))
 images=[bytearray(b'\xff'*(end-start)) for start,end in POOLS];addresses=[];pool=0;used=0
 for record in records:
  size=len(record)
  if used+size+3>len(images[pool]):
   assert pool+1<len(POOLS),'SFX data exceeds reclaimed audio RAM'
   images[pool][used:used+3]=b'\0'+struct.pack('<H',POOLS[pool+1][0]);pool+=1;used=0
  addresses.append(POOLS[pool][0]+used)
  images[pool][used:used+size]=record;used+=size
 for index,offset,dest in fixups:
  addr=addresses[index]+offset;p=next(n for n,(start,end) in enumerate(POOLS) if start<=addr<end)
  off=addr-POOLS[p][0];images[p][off:off+2]=struct.pack('<H',addresses[dest])
 for n,data in enumerate(images):(B/f'sfx-runs-{n}.bin').write_bytes(data)
 (B/'sfx-table.inc').write_text(f'sfx_note_table equ ${addresses[table]:04X}\n'+''.join(f'    dw ${e["source"]:04X},${addresses[e["record"]]:04X}\n    db {int(e["narrow"])}\n' for e in effects))
 report=dict(bytes=sum(map(len,records))+3*pool,note_variants=len(notes),volume_profiles=len(profiles),pools=[list(p) for p in POOLS],effects=effects)
 (B/'sfx-build.json').write_text(json.dumps(report,indent=2)+'\n')
 return list(zip(POOLS,images))
if __name__=='__main__':compile_effects();print((B/'sfx-build.json').read_text())
