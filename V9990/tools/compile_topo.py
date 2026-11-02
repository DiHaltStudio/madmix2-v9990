"""Compile original Topo actor paths into interpolated, double-buffered P1 tile frames."""
import json,struct
from pathlib import Path
from PIL import Image

def compile_topo(root):
 a=root/'topo';j=json.loads((a/'animation.json').read_text());keys=j['frames'];images={n:Image.open(a/n) for n in {p['image'] for f in keys for p in f['actors']}}
 panels=[Image.open(a/n) for n in j['panels']];canvas=Image.new('L',(256,192))
 def render(actors,k):
  im=canvas.copy()
  for i in range(max(0,k-39)):
   panel=panels[i];im.paste(panel.convert('L').point(lambda v:int(v>0)),[(96,107),(40,99),(32,91)][i])
  for row in actors:
   src=images[row['image']];pixels=src.tobytes();ink=Image.frombytes('L',src.size,bytes(int(v==1) for v in pixels));mask=Image.frombytes('L',src.size,bytes(255 if v else 0 for v in pixels));im.paste(ink,(row['x'],row['y']),mask)
  return im
 frames=[]
 for k,f in enumerate(keys):
  prev=keys[k-1]['actors'] if k else f['actors'];cur=f['actors']
  if len(prev)!=len(cur):
   # Actors entering from the screen edge use their exact original start positions.
   prev=prev+[dict(r,x=x,y=y) for r,x,y in zip(cur[len(prev):],[40,40,208,0],[-39,192,65,65])]
  for step in range(1,5):
   rows=[dict(q,x=round(p['x']+(q['x']-p['x'])*step/4),y=round(p['y']+(q['y']-p['y'])*step/4)) for p,q in zip(prev,cur)]
   frames.append(render(rows,k))
 # A short final hold, kept as repeated frames for constant 50Hz publication.
 frames += [frames[-1]]*22
 tiles=[bytes(64)];lookup={tiles[0]:0};stream=bytearray();sizes=[]
 for im in frames:
  start_frame=len(stream)
  for y in range(24):
   names=[]
   for x in range(32):
    tile=im.crop((x*8,y*8,x*8+8,y*8+8)).tobytes()
    if tile not in lookup:lookup[tile]=len(tiles);tiles.append(tile)
    names.append(4096+lookup[tile])
   i=0
   while i<32:
    run=1
    while i+run<32 and names[i+run]==names[i]:run+=1
    if run>=3:
     stream+=bytes([128+run])+struct.pack('<H',names[i]);i+=run
    else:
     start=i;i+=run
     while i<32:
      run=1
      while i+run<32 and names[i+run]==names[i]:run+=1
      if run>=3:break
      i+=run
     stream+=bytes([i-start])+struct.pack('<'+'H'*(i-start),*names[start:i])
  size=len(stream)-start_frame;sizes.append(size)
  if start_frame//16384 != (len(stream)-1)//16384:
   frame=stream[start_frame:];del stream[start_frame:]
   stream+=bytes([255])*(16384-len(stream)%16384);stream+=frame
 assert len(tiles)<=3584, len(tiles)
 return tiles,stream,frames
