# Dibuja una grilla con medidas (una raya cada 10 cm, numeros cada 20) sobre las vistas que saca medir.py.
# Uso, desde la raiz del proyecto:  py tools/animales/grilla.py guanaco
import sys, json
from PIL import Image, ImageDraw
SAL = '.revision/animales'
EJES = 'xyz'
for nombre in sys.argv[1:]:
    info = json.load(open('%s/medida_%s.json' % (SAL, nombre)))
    for vista, d in info.items():
        im = Image.open('%s/medida_%s_%s.png' % (SAL, nombre, vista)).convert('RGB')
        dr = ImageDraw.Draw(im)
        W, H, ppm, cen = d['W'], d['H'], d['ppm'], d['cen']
        ih = max(range(3), key=lambda i: abs(d['der'][i])); sh = 1 if d['der'][ih] > 0 else -1
        iv = max(range(3), key=lambda i: abs(d['arr'][i])); sv = 1 if d['arr'][iv] > 0 else -1
        def px(valor): return W / 2 + sh * (valor - cen[ih]) * ppm
        def py(valor): return H / 2 - sv * (valor - cen[iv]) * ppm
        k = -40
        while k <= 40:
            v = k / 10
            for horizontal in (True, False):
                p = px(v) if horizontal else py(v)
                lim = W if horizontal else H
                if 0 <= p < lim:
                    fuerte = k % 5 == 0
                    col = (255, 0, 0) if k == 0 else ((60, 60, 200) if fuerte else (150, 150, 150))
                    if horizontal:
                        dr.line([(p, 0), (p, H)], fill=col, width=1)
                        if k % 2 == 0: dr.text((p + 2, 2), '%s%.1f' % (EJES[ih], v), fill=(0, 0, 0))
                    else:
                        dr.line([(0, p), (W, p)], fill=col, width=1)
                        if k % 2 == 0: dr.text((2, p + 1), '%s%.1f' % (EJES[iv], v), fill=(0, 0, 0))
            k += 1
        im.save('%s/medida_%s_%s_g.jpg' % (SAL, nombre, vista), quality=85)
    print('grilla', nombre)
