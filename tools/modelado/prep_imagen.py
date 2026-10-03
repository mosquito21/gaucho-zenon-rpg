# Recorta el fondo (rembg u2net) y tapa la estrella de Gemini. Se corre con el python de Hunyuan.
import sys, os
from PIL import Image
from rembg import remove, new_session
salida_dir = sys.argv[1]
os.makedirs(salida_dir, exist_ok=True)
sesion = new_session('u2net')
for ruta in sys.argv[2:]:
    im = Image.open(ruta).convert('RGB')
    w, h = im.size
    lado = int(min(w, h) * 0.12)
    fondo = im.getpixel((w - lado - 8, h - lado // 2))        # color del fondo al lado de la estrella
    im.paste(fondo, (w - lado, h - lado, w, h))
    rgba = remove(im, session=sesion)
    px = rgba.load()
    for y in range(h - lado, h):
        for x in range(w - lado, w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 0)
    caja = rgba.getbbox()
    margen = 24
    caja = (max(0, caja[0] - margen), max(0, caja[1] - margen), min(w, caja[2] + margen), min(h, caja[3] + margen))
    rgba = rgba.crop(caja)
    destino = os.path.join(salida_dir, os.path.splitext(os.path.basename(ruta))[0] + '.png')
    rgba.save(destino)
    alfa = rgba.split()[3]
    print('PREP', os.path.basename(destino), rgba.size, 'cubierto %.0f%%' % (100.0 * sum(1 for v in alfa.getdata() if v > 128) / (rgba.size[0] * rgba.size[1])))
