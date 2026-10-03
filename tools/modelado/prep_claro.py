# Como prep_imagen.py, pero rescata la ropa clara de los brazos que rembg borra contra el fondo gris:
# en las filas de los brazos se suma un recorte por "balde de pintura" hecho desde los bordes.
import sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from rembg import remove, new_session
origen, destino = sys.argv[1], sys.argv[2]
im = Image.open(origen).convert('RGB')
w, h = im.size
lado = int(min(w, h) * 0.12)
im.paste(im.getpixel((w - lado - 8, h - lado // 2)), (w - lado, h - lado, w, h))
alfa = remove(im, session=new_session('u2net')).split()[3]
marca = (255, 0, 255)
trabajo = im.copy()
for x in range(0, w, 16):
    for y in (0, h - 1):
        if trabajo.getpixel((x, y)) != marca:
            ImageDraw.floodfill(trabajo, (x, y), marca, thresh=12)
for y in range(0, h, 16):
    for x in (0, w - 1):
        if trabajo.getpixel((x, y)) != marca:
            ImageDraw.floodfill(trabajo, (x, y), marca, thresh=12)
relleno = Image.new('L', (w, h), 255)
rp = relleno.load(); tp = trabajo.load()
for y in range(h):
    for x in range(w):
        if tp[x, y] == marca:
            rp[x, y] = 0
relleno = relleno.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(5))      # saca motas
# filas de los brazos: donde la figura (segun rembg) es casi tan ancha como en su fila mas ancha
ap = alfa.load()
anchos = []
for y in range(h):
    xs = [x for x in range(w) if ap[x, y] > 128]
    anchos.append((xs[-1] - xs[0]) if xs else 0)
tope = max(anchos)
filas = [y for y, a in enumerate(anchos) if a > 0.85 * tope]
y0, y1 = max(0, min(filas) - 30), min(h, max(filas) + 30)
banda = Image.new('L', (w, h), 0)
banda.paste(relleno.crop((0, y0, w, y1)), (0, y0))
final = ImageChops.lighter(alfa, banda.filter(ImageFilter.GaussianBlur(0.7)))
rgba = im.convert('RGBA'); rgba.putalpha(final)
caja = rgba.getbbox(); m = 24
rgba = rgba.crop((max(0, caja[0]-m), max(0, caja[1]-m), min(w, caja[2]+m), min(h, caja[3]+m)))
rgba.save(destino)
fondo = Image.new('RGBA', rgba.size, (150, 40, 130, 255)); fondo.alpha_composite(rgba)
fondo.convert('RGB').resize((rgba.width * 3 // 4, rgba.height * 3 // 4)).save(destino.replace('.png', '_ver.jpg'), quality=88)
print('PREP CLARO', destino, rgba.size, 'filas de brazos', y0, y1)
