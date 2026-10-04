#!/usr/bin/env python3
# Analiza el vga.hex de tb_sd (un caracter en base 32 por ciclo de 25 MHz:
# bit 0 B, 1 R, 2 G, 3 DE, 4 HS activa; una linea de texto por linea VGA,
# con "S" delante si la vsync esta activa) y dice, por trama:
#   - lineas, duracion de la hsync y de la vsync
#   - donde empieza la imagen respecto a la hsync y a la vsync, en us y en
#     lineas, y donde cae su centro (comparado con TV y VGA)
#   - que lineas de la maquina salen (la VRAM de prueba lleva y codificada)
#     y si se ven las columnas x = 0 y x = 639
# Con un nombre de PNG guarda dos imagenes de la ultima trama:
#   X.png           solo la zona activa, punto a punto (640 de ancho)
#   X_completa.png  el cuadro entero, un pixel por ciclo de 25 MHz; hsync en
#                   gris, vsync en magenta, blanking en azul oscuro
#
#   /usr/bin/python3 analiza_sd.py [--s1] vga.hex [salida.png]
#   --s1: Screen 1 a 400 lineas (tb_sd +SCREEN1): cada linea es una raster
#         r = 0..399 de la pagina mono, en blanco
import sys
from collections import Counter

T = 0.04   # us por ciclo: 25 MHz, o 25,1436 con fp1100_vga (525 lineas)

def tramas_de(fich):
    tramas, actual = [], None
    for raw in open(fich).read().replace("#trama\n", "\n#trama\n").split("\n"):
        if raw.startswith("#trama"):
            actual = []
            tramas.append(actual)
            continue
        if actual is None or not raw:
            continue
        actual.append((raw[0] == "S", [int(c, 32) for c in raw[1:]]))
    tramas = tramas[:-1]                     # la ultima puede ir a medias
    # la primera linea de cada trama es un trozo (empieza en la vsync)
    return [[l for l in t if len(l[1]) > 100] for t in tramas if t]

def analiza(trama, png=None):
    global T
    n = len(trama)
    T = 1 / 25.14368 if n in (524, 525, 526) else 0.04
    largos = Counter(len(p) for _, p in trama)
    hs_len = Counter(sum(1 for c in p if c & 16) for _, p in trama)
    vs_lin = [i for i, (vs, _) in enumerate(trama) if vs]
    activas = [i for i, (_, p) in enumerate(trama) if any(c & 8 for c in p)]
    largo = largos.most_common(1)[0][0]
    w = 2 if largo > 1000 else 1               # ciclos por punto
    print(f"  lineas: {n}  ciclos por linea: {dict(largos)}  ({largo*T:.3f} us, {1000/(largo*T):.3f} kHz, "
          f"{1e6/(sum(len(p) for _, p in trama)*T):.3f} Hz)")
    hs = hs_len.most_common(1)[0][0]
    print(f"  hsync: {hs} ciclos = {hs*T:.2f} us  (TV 4,7 us; VGA 3,84 us)")
    if not activas:
        print("  sin lineas activas")
        return
    v0 = vs_lin[0] if vs_lin else 0
    v1 = vs_lin[-1] + 1 if vs_lin else 0
    print(f"  vsync: {len(vs_lin)} lineas ({vs_lin[0] if vs_lin else '-'}..{vs_lin[-1] if vs_lin else '-'})"
          f"  (VGA: 2)" if w == 1 else f"  vsync: {len(vs_lin)} lineas")
    print(f"  imagen: lineas {activas[0]}..{activas[-1]} ({len(activas)}); empieza {activas[0]-v0} lineas "
          f"tras el principio de la vsync y {activas[0]-v1} tras su final; quedan {n-1-activas[-1]} debajo")
    if w == 1:
        print(f"         VGA 640x480: la ventana de 480 empieza 35 lineas tras el principio de la vsync; "
              f"la imagen queda con {activas[0]-v0-35} lineas encima y {35+480-1-activas[-1]+v0} debajo")
    p = trama[activas[0]][1]
    s = next(k for k, c in enumerate(p) if c & 8)
    e = max(k for k, c in enumerate(p) if c & 8) + 1
    centro = (s + e) / 2 * T
    print(f"  horizontal: imagen de {s*T:.2f} a {e*T:.2f} us desde el flanco de la hsync "
          f"({(e-s)//w} puntos), centro {centro:.2f} us; porche trasero {(s-hs)*T:.2f} us, "
          f"delantero {(largo-e)*T:.2f} us")
    if w == 2:
        print(f"         TV (BT.601/NTSC): activa 52,6 us desde ~9,4-10,0 us, centro ~35,6 us -> "
              f"{(centro-35.6)/0.08:+.1f} puntos")
    else:
        print(f"         VGA: activa desde el ciclo 144 (96+48), centro en 464 -> "
              f"{(s+e)/2-464:+.1f} puntos")
    ys, img = [], []
    for i in activas:
        p = trama[i][1]
        s = next(k for k, c in enumerate(p) if c & 8)
        px = [p[s + x * w] & 7 if s + x * w < len(p) and (p[s + x * w] & 8) else None for x in range(640)]
        img.append(px)
        yb = sum(((px[x] or 0) & 1) << k for k, x in enumerate(range(16, 24)))
        yr = sum((((px[x] or 0) >> 1) & 1) << k for k, x in enumerate(range(24, 32)))
        if S1:      # mono: raster r en los puntos 16-23 (bits 7-0) y 24 (bit 8)
            yb = sum((1 if px[x] else 0) << k for k, x in enumerate(range(16, 24))) | ((1 if px[24] else 0) << 8)
            yr = yb
        if None not in px and all(c == 7 for c in px):
            ys.append("blanca")
        elif all((c or 0) == 0 for c in px):
            ys.append("borde")
        elif yb == yr and yb != 0:
            ys.append(yb)
        else:
            ys.append(f"?{yb}/{yr}")
    num = [y for y in ys if isinstance(y, int)]
    ultima = 399 if S1 else 199
    falta = [y for y in range(1, ultima) if y not in num]
    print(f"  lineas de la maquina: y 1..{ultima-1} {sorted(set(Counter(num).values()))} veces cada una, faltan {len(falta)}"
          f"; lineas blancas (y=0, y=199): {ys.count('blanca')}")
    borde = [activas[k] for k, y in enumerate(ys) if y == "borde"]
    if borde:
        con = [activas[k] for k, y in enumerate(ys) if y != "borde"]
        print(f"  dentro de la ventana activa: {len(borde)} lineas de borde; imagen en las lineas {con[0]}..{con[-1]} "
              f"({len(con)}): {con[0]-v0} tras el principio de la vsync, {con[0]-activas[0]} lineas de borde encima "
              f"y {activas[-1]-con[-1]} debajo")
    raras = [(activas[k], y) for k, y in enumerate(ys) if isinstance(y, str) and y not in ("blanca", "borde")]
    if raras:
        print(f"  lineas raras: {raras[:12]}")
    print(f"  x=0 en {sum(1 for r in img if r[0] == 7)} de {len(img)} lineas; x=639 en {sum(1 for r in img if r[639] == 7)}")
    if png:
        try:
            from PIL import Image
        except ImportError:
            print("  (sin PIL: usar /usr/bin/python3 para las imagenes)")
            return
        col = lambda c: (255 * ((c >> 1) & 1), 255 * ((c >> 2) & 1), 255 * (c & 1))
        im = Image.new("RGB", (640, len(img)))
        for yy, r in enumerate(img):
            for xx, c in enumerate(r):
                im.putpixel((xx, yy), (0, 0, 64) if c is None else col(c))
        im = im.resize((1280, len(img) * (2 if w == 1 else 4)), Image.NEAREST)
        im.save(png)
        ancho = max(len(p) for _, p in trama)
        im2 = Image.new("RGB", (ancho, n), (40, 40, 40))
        for yy, (vs, p) in enumerate(trama):
            for xx, c in enumerate(p):
                if c & 16:
                    v = (128, 128, 128)
                elif vs:
                    v = (160, 0, 160)
                elif not c & 8:
                    v = (0, 0, 60)
                else:
                    v = col(c)
                im2.putpixel((xx, yy), v)
        if w == 2:                          # 15 kHz: lineas al doble de alto
            im2 = im2.resize((ancho // 2, n * 2), Image.NEAREST)
        im2 = im2.resize((im2.width * 2, im2.height * 2), Image.NEAREST)
        completa = png.replace(".png", "_completa.png")
        im2.save(completa)
        print(f"  -> {png}, {completa}")

S1 = False
if __name__ == "__main__":
    if sys.argv[1] == "--s1":
        S1 = True
        del sys.argv[1]
    tramas = tramas_de(sys.argv[1])
    for k, t in enumerate(tramas):
        print(f"trama {k}:")
        analiza(t, sys.argv[2] if len(sys.argv) > 2 and k == len(tramas) - 1 else None)
