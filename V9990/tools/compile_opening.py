"""User artwork -> Sol Negro-style B3/BD8, preserving complete image aspect ratio."""
from PIL import Image, ImageOps
from pathlib import Path
import hashlib,json

def compile_opening(assets,build):
    source=assets/'opening/opening.jpeg'
    original=ImageOps.exif_transpose(Image.open(source)).convert('RGB')
    fitted=ImageOps.contain(original,(512,424),Image.Resampling.LANCZOS)
    palette=[]
    for code in range(256):
        palette.extend((((code>>2)&7)*255//7,((code>>5)&7)*255//7,(code&3)*255//3))
    reference=Image.new('P',(1,1));reference.putpalette(palette)
    pixels=fitted.quantize(palette=reference,dither=Image.Dither.FLOYDSTEINBERG)
    image=Image.new('P',(512,424),0);image.putpalette(palette)
    image.paste(pixels,((512-fitted.width)//2,(424-fitted.height)//2))
    image.save(build/'opening-b3.png')
    blob=image.tobytes();(build/'opening-b3.bin').write_bytes(blob)
    (build/'opening-b3.json').write_text(json.dumps({'source':str(source.relative_to(assets)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'mode':'B3/BD8','size':[512,424],'picture_size':list(fitted.size),'colors':256,'bytes':len(blob)},indent=2)+'\n')
    return blob
