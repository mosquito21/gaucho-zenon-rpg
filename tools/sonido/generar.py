# -*- coding: utf-8 -*-
"""Genera los sonidos de ambiente de El Gaucho Zenón (tanda 8): viento, pasos, cascos, fuego,
hacienda y unos pocos más. No usa ninguna grabación: todo sale de ruido filtrado, golpes cortos
y voces armadas con una fuente y sus resonancias. Los archivos van a audio/ambiente/.

    py tools/sonido/generar.py            genera todo
    py tools/sonido/generar.py viento     genera solo los que empiezan con ese nombre

Los que se repiten (viento, fuego, tropel, grillos, rio) se arman "en redondo": el final empalma
con el principio, así que el juego los repite sin que se note. Esos se guardan en OGG (hace falta
ffmpeg en el PATH); los cortos, en WAV. Las semillas son fijas: correrlo dos veces da lo mismo.
Para ver cómo quedó cada uno (el agente que los hizo no oye): py tools/sonido/ver.py
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100
AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.normpath(os.path.join(AQUI, '..', '..', 'audio', 'ambiente'))


# ---------------------------------------------------------------- piezas

def db(x):
    return 10.0 ** (x / 20.0)


def normalizar(x, pico_db=-3.0):
    x = x - np.mean(x, axis=0)
    tope = np.max(np.abs(x))
    return x * (db(pico_db) / tope) if tope > 0 else x


def banda(f, desde, hasta, orden=3):
    """Cuánto deja pasar de cada frecuencia un filtro de banda suave (sin fase: se usa sobre el espectro)."""
    f = np.maximum(f, 1e-6)
    return 1.0 / np.sqrt(1.0 + (desde / f) ** (2 * orden)) / np.sqrt(1.0 + (f / hasta) ** (2 * orden))


def ruido_con_forma(n, forma, r):
    """Ruido con el espectro que diga forma(f). Como se arma sobre el espectro, empalma en redondo."""
    espectro = np.fft.rfft(r.standard_normal(n))
    y = np.fft.irfft(espectro * forma(np.fft.rfftfreq(n, 1.0 / SR)), n)
    return y / (np.std(y) + 1e-12)


def lento(n, r, hasta_hz, desde_hz=0.0):
    """Una curva suave al azar entre 0 y 1 (ruido con solo sus frecuencias bajas). Empalma en redondo."""
    espectro = np.fft.rfft(r.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    espectro[(f > hasta_hz) | (f < desde_hz)] = 0.0
    espectro[0] = 0.0
    y = np.fft.irfft(espectro, n)
    return (y - y.min()) / (y.max() - y.min() + 1e-12)


def filtro(x, desde, hasta, orden=2):
    """Filtro de banda común, para los sonidos cortos (no empalma en redondo)."""
    tope = SR * 0.49
    if desde <= 0:
        sos = signal.butter(orden, min(hasta, tope), 'low', fs=SR, output='sos')
    elif hasta >= tope:
        sos = signal.butter(orden, desde, 'high', fs=SR, output='sos')
    else:
        sos = signal.butter(orden, [desde, min(hasta, tope)], 'band', fs=SR, output='sos')
    return signal.sosfilt(sos, x)


def cae(n, tau_s, ataque_s=0.002):
    """Envolvente de golpe: sube en un instante y cae sola."""
    t = np.arange(n) / SR
    return np.minimum(t / max(ataque_s, 1e-5), 1.0) * np.exp(-t / tau_s)


def meseta(n, ataque_s, salida_s):
    """Envolvente de voz: entra suave, se sostiene y sale suave."""
    e = np.ones(n)
    a = max(int(ataque_s * SR), 1)
    s = max(int(salida_s * SR), 1)
    e[:a] = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    e[-s:] = 0.5 + 0.5 * np.cos(np.pi * np.arange(s) / s)
    return e


def barrido(n, f_ini, f_fin, tau_s):
    """Un tono que baja (o sube) de f_ini a f_fin, rápido al principio."""
    t = np.arange(n) / SR
    f = f_fin + (f_ini - f_fin) * np.exp(-t / tau_s)
    return np.sin(2.0 * np.pi * np.cumsum(f) / SR)


def sumar(y, pieza, donde, redondo=False):
    """Suma una pieza corta dentro de un sonido largo, desde esa muestra (dando la vuelta si es en redondo)."""
    if redondo:
        y[(donde + np.arange(pieza.size)) % y.size] += pieza
    else:
        fin = min(donde + pieza.size, y.size)
        if fin > donde:
            y[donde:fin] += pieza[:fin - donde]


def cerrar(x, entra_ms=1.5, sale_ms=15.0):
    """Los cortos empiezan y terminan en cero, para que no hagan clic."""
    x = x.copy()
    a = int(SR * entra_ms / 1000.0)
    s = int(SR * sale_ms / 1000.0)
    x[:a] *= np.linspace(0.0, 1.0, a)
    x[-s:] *= np.linspace(1.0, 0.0, s) ** 2
    return x


def voz(dur, f0, formantes, r, caida=1.2, temblor=0.012, ronquera=0.0, aire=0.03, tope_hz=6500.0):
    """Una voz de animal: una fuente con sus armónicos (el tono f0) y las resonancias de la boca
    (formantes: frecuencia, ancho y peso). f0 y cada frecuencia de formante pueden ser un número o
    una función de u, que va de 0 al empezar a 1 al terminar."""
    n = int(dur * SR)
    u = np.linspace(0.0, 1.0, n, endpoint=False)
    tono = f0(u) if callable(f0) else np.full(n, float(f0))
    # Ninguna garganta es una máquina: el tono tiembla apenas.
    tono = tono * (1.0 + temblor * (2.0 * lento(n, r, 14.0) - 1.0))
    fase = 2.0 * np.pi * np.cumsum(tono) / SR
    curvas = [(F(u) if callable(F) else np.full(n, float(F)), ancho, peso) for F, ancho, peso in formantes]
    y = np.zeros(n)
    k = 1
    while k * tono.min() < tope_hz:
        fk = k * tono
        resonancia = np.zeros(n)
        for F, ancho, peso in curvas:
            resonancia += peso / np.sqrt(1.0 + ((fk - F) / (ancho * 0.5)) ** 2)
        y += k ** -caida * resonancia * (fk < tope_hz) * np.sin(k * fase + r.uniform(0.0, 2.0 * np.pi))
        k += 1
    if ronquera > 0.0:
        # Un pulso de cada dos sale más flojo: la ronquera del que brama.
        y *= 1.0 - ronquera * (0.5 + 0.5 * np.sin(fase * 0.5))
    if aire > 0.0:
        soplo = r.standard_normal(n)
        centro = float(np.mean(curvas[0][0]))
        y += filtro(soplo, centro * 0.6, centro * 4.0) * aire * np.std(y) / 0.3
    return y


# ---------------------------------------------------------------- los que se repiten

def viento():
    """El viento de la estepa: un soplo ancho cuyo tono sube y baja con la racha, el roce del pasto
    cuando arrecia y un fondo grave que no se va nunca. En estéreo: cada oído, su propio ruido."""
    n = int(32.0 * SR)
    r = np.random.default_rng(1881)
    racha = lento(n, r, 0.45) ** 1.6
    centro = 170.0 * 2.0 ** (2.2 * racha)
    centros = 90.0 * 2.0 ** np.arange(0.0, 6.01, 0.5)
    canales = []
    for _ in range(2):
        y = np.zeros(n)
        for fc in centros:
            b = ruido_con_forma(n, lambda f, fc=fc: np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / fc) / 0.30) ** 2), r)
            peso = np.exp(-0.5 * (np.log2(fc / centro) / 0.9) ** 2)
            y += b * peso * (fc / 300.0) ** -0.4
        y *= 0.3 + 0.7 * racha
        pasto = ruido_con_forma(n, lambda f: banda(f, 3200.0, 8500.0), r)
        y += pasto * 0.035 * racha ** 2 * (0.4 + 0.6 * lento(n, r, 3.0))
        fondo = ruido_con_forma(n, lambda f: banda(f, 35.0, 140.0, 2), r)
        y += fondo * 0.3 * (0.7 + 0.3 * lento(n, r, 0.3))
        canales.append(y)
    return normalizar(np.stack(canales, axis=1), -3.0)


def fuego():
    """Un fogón: el rumor grave de la llama, que late; el siseo de la leña; y el chisporroteo, que
    son muchísimos golpecitos cortos de ruido, cada uno con su tono, a ratos más y a ratos menos."""
    n = int(14.0 * SR)
    r = np.random.default_rng(7)
    y = ruido_con_forma(n, lambda f: banda(f, 40.0, 260.0, 2), r) * 0.055 * (0.5 + 0.9 * lento(n, r, 7.0, 1.5))
    y += ruido_con_forma(n, lambda f: banda(f, 2200.0, 8000.0, 2), r) * 0.2 * lento(n, r, 9.0) ** 4
    actividad = 0.25 + 0.75 * lento(n, r, 0.8)
    for _ in range(int(14.0 * 22)):
        donde = int(r.integers(n))
        if r.random() > actividad[donde]:
            continue
        largo = int(SR * r.uniform(0.0006, 0.005))
        fc = r.uniform(1500.0, 7000.0)
        grano = np.concatenate([r.standard_normal(largo) * np.exp(-np.arange(largo) / (largo / 4.0)), np.zeros(96)])
        sumar(y, filtro(grano, fc * 0.7, fc * 1.4) * min(r.lognormal(-1.5, 0.9), 1.0), donde, True)
    for _ in range(9):
        # De vez en cuando revienta un nudo: más grave y más largo.
        largo = int(SR * r.uniform(0.012, 0.03))
        fc = r.uniform(450.0, 1400.0)
        grano = np.concatenate([r.standard_normal(largo) * cae(largo, largo / SR / 5.0, 0.0005), np.zeros(256)])
        sumar(y, filtro(grano, fc * 0.6, fc * 1.6) * r.uniform(0.6, 1.0), int(r.integers(n)), True)
    return normalizar(y, -2.0)


def tropel(cascos):
    """Muchos cascos a la vez: el rebaño que anda. Se arma mezclando los cascos de Ceniza."""
    n = int(8.0 * SR)
    r = np.random.default_rng(31)
    y = np.zeros(n)
    cuantos = int(8.0 * 13)
    for k in range(cuantos):
        c = cascos[int(r.integers(len(cascos)))]
        # Cada animal pesa distinto: el mismo golpe, un poco más grave o más agudo.
        c = signal.resample(c, int(c.size * r.uniform(0.86, 1.2)))
        # Repartidos parejo, cada uno corrido al azar dentro de su turno: del todo al azar quedaban
        # huecos de un cuarto de segundo, que al repetirse se oyen como un tropezón.
        sumar(y, c * r.uniform(0.25, 1.0), int((k + r.uniform(0.0, 1.0)) / cuantos * n) % n, True)
    return normalizar(y, -3.0)


def grillos():
    """Grillos de noche de verano: cada uno canta tres pulsos de un tono muy agudo, a su ritmo."""
    dur = 12.0
    n = int(dur * SR)
    r = np.random.default_rng(12)
    y = np.zeros(n)
    t_pulso = np.arange(int(0.015 * SR)) / SR
    for tono, cantos, fuerza in [(4250.0, 25, 1.0), (4520.0, 31, 0.55), (4700.0, 22, 0.4), (4950.0, 28, 0.28), (5200.0, 35, 0.2)]:
        desfase = r.uniform(0.0, dur / cantos)
        for c in range(cantos):
            # Un número entero de cantos por vuelta, así el empalme no corta ninguno.
            inicio = desfase + c * dur / cantos + r.normal(0.0, 0.012)
            parejo = fuerza * r.uniform(0.75, 1.0)
            for p in range(3):
                pulso = np.sin(2.0 * np.pi * tono * t_pulso) * np.sin(np.pi * t_pulso / t_pulso[-1]) ** 2
                sumar(y, pulso * parejo, int((inicio + p * 0.031) * SR) % n, True)
    return normalizar(y, -6.0)


def rio():
    """El Limay de cerca: el agua que corre (un soplo parejo) y el borboteo (burbujitas que suben de tono)."""
    n = int(12.0 * SR)
    r = np.random.default_rng(3)
    y = ruido_con_forma(n, lambda f: banda(f, 300.0, 1900.0, 2) * np.maximum(f, 50.0) ** -0.5, r) * (0.75 + 0.25 * lento(n, r, 0.9))
    burbujas = np.zeros(n)
    for _ in range(int(12.0 * 26)):
        largo = int(SR * r.uniform(0.008, 0.028))
        f_ini = r.uniform(500.0, 2400.0)
        t = np.arange(largo) / SR
        f = f_ini * (1.0 + r.uniform(0.3, 0.8) * t / t[-1])
        gota = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) * np.exp(-t / (largo / SR / 2.5))
        sumar(burbujas, gota * r.uniform(0.2, 1.0), int(r.integers(n)), True)
    y += burbujas * 2.2
    return normalizar(y, -4.0)


# ---------------------------------------------------------------- pasos y cascos

def paso(i):
    """Una pisada de bota de potro en tierra seca con pasto: el golpe sordo del talón y, un instante
    después, el roce de la planta en el pasto seco."""
    r = np.random.default_rng(100 + i)
    n = int(0.27 * SR)
    y = barrido(n, r.uniform(90.0, 115.0), r.uniform(50.0, 62.0), 0.018) * cae(n, r.uniform(0.02, 0.03)) * 0.6
    y += filtro(r.standard_normal(n), 120.0, r.uniform(700.0, 1100.0)) * cae(n, r.uniform(0.022, 0.035)) * 1.1
    roce = filtro(r.standard_normal(n), r.uniform(1100.0, 1600.0), r.uniform(3800.0, 5200.0))
    crujido = lento(n, r, 160.0, 25.0) ** 2
    atraso = int(SR * r.uniform(0.008, 0.024))
    roce *= np.concatenate([np.zeros(atraso), cae(n - atraso, r.uniform(0.04, 0.065), 0.006)]) * crujido
    y += roce * r.uniform(1.1, 1.6)
    return normalizar(cerrar(y), -6.0)


def paso_ripio(i):
    """La misma pisada sobre canto rodado: piedritas que se corren y se golpean."""
    r = np.random.default_rng(200 + i)
    n = int(0.3 * SR)
    y = filtro(r.standard_normal(n), 100.0, 900.0) * cae(n, 0.025) * 0.9
    for _ in range(int(r.integers(26, 40))):
        largo = int(SR * r.uniform(0.001, 0.004))
        fc = r.uniform(1100.0, 4800.0)
        grano = np.concatenate([r.standard_normal(largo) * np.exp(-np.arange(largo) / (largo / 3.0)), np.zeros(64)])
        sumar(y, filtro(grano, fc * 0.7, fc * 1.4) * r.uniform(0.15, 0.8), int(SR * abs(r.normal(0.03, 0.05))))
    for _ in range(int(r.integers(3, 6))):
        # Dos piedras que chocan: un tic con tono.
        largo = int(SR * 0.02)
        tic = np.sin(2.0 * np.pi * r.uniform(1300.0, 3200.0) * np.arange(largo) / SR) * cae(largo, r.uniform(0.002, 0.005), 0.0003)
        sumar(y, tic * r.uniform(0.2, 0.55), int(SR * r.uniform(0.0, 0.12)))
    return normalizar(cerrar(y), -6.0)


def paso_agua(i):
    """Vadear: el pie que entra al agua, el chapoteo y unas burbujas."""
    r = np.random.default_rng(300 + i)
    n = int(0.5 * SR)
    y = barrido(n, 85.0, 48.0, 0.03) * cae(n, 0.05, 0.004) * 0.35
    y += filtro(r.standard_normal(n), r.uniform(250.0, 400.0), r.uniform(2200.0, 3200.0)) * cae(n, r.uniform(0.09, 0.14), 0.012) * (0.5 + 0.5 * lento(n, r, 40.0))
    for _ in range(int(r.integers(7, 12))):
        largo = int(SR * r.uniform(0.02, 0.055))
        t = np.arange(largo) / SR
        f = r.uniform(380.0, 950.0) * (1.0 + r.uniform(0.6, 1.3) * t / t[-1])
        gota = np.sin(2.0 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) * np.exp(-t / (largo / SR / 2.0))
        sumar(y, gota * r.uniform(0.12, 0.4), int(SR * r.uniform(0.02, 0.3)))
    return normalizar(cerrar(y, 1.5, 40.0), -6.0)


def casco(i):
    """Un vaso sin herrar sobre tierra: un golpe sordo y pesado, el "toc" corto del vaso y la tierra
    que se corre. Sin el clac de la herradura en el empedrado."""
    r = np.random.default_rng(400 + i)
    n = int(0.22 * SR)
    y = barrido(n, r.uniform(120.0, 140.0), r.uniform(55.0, 66.0), 0.02) * cae(n, r.uniform(0.026, 0.034), 0.0015) * 0.6
    y += np.sin(2.0 * np.pi * r.uniform(300.0, 430.0) * np.arange(n) / SR) * cae(n, r.uniform(0.008, 0.012), 0.0008) * 0.5
    y += filtro(r.standard_normal(n), 150.0, r.uniform(1200.0, 1700.0)) * cae(n, r.uniform(0.018, 0.026)) * 1.6
    y += filtro(r.standard_normal(n), 1500.0, 4200.0) * cae(n, r.uniform(0.008, 0.014)) * 0.25
    return normalizar(cerrar(y), -4.0)


# ---------------------------------------------------------------- hacienda

def mugido(i):
    """Una vaca que muge lejos: empieza con la boca cerrada (grave y nasal), abre, sube y vuelve a bajar."""
    r = np.random.default_rng(500 + i)
    dur = [1.9, 1.5, 2.3][i % 3]
    sube = [1.0, 1.12, 0.92][i % 3]
    tono = lambda u: np.interp(u, [0.0, 0.3, 0.68, 1.0], [86.0, 132.0 * sube, 148.0 * sube, 94.0])
    abre = lambda u: np.clip((u - 0.12) / 0.22, 0.0, 1.0)
    y = voz(dur, tono, [
        (lambda u: 250.0 + 230.0 * abre(u), 110.0, 1.0),
        (lambda u: 1000.0 - 130.0 * abre(u), 220.0, 0.55),
        (2350.0, 350.0, 0.2),
    ], r, caida=1.25, temblor=0.015, ronquera=0.22, aire=0.03)
    y *= meseta(y.size, 0.2, 0.4)
    return normalizar(filtro(y, 60.0, 5500.0), -5.0)


def balido(i):
    """Una oveja: un "meee" corto y tembloroso. El carnero, lo mismo más grave."""
    r = np.random.default_rng(600 + i)
    dur = [0.85, 0.7, 1.0][i % 3]
    base = [395.0, 430.0, 255.0][i % 3]
    late = r.uniform(7.5, 9.0)
    n = int(dur * SR)
    t = np.arange(n) / SR
    tono = lambda u: base * np.interp(u, [0.0, 0.25, 1.0], [0.93, 1.05, 0.86]) * (1.0 + 0.03 * np.sin(2.0 * np.pi * late * u * dur))
    y = voz(dur, tono, [(720.0, 150.0, 1.0), (1850.0, 240.0, 0.7), (2850.0, 350.0, 0.35)], r, caida=0.95, temblor=0.03, ronquera=0.3, aire=0.05)
    y *= 0.58 + 0.42 * np.sin(2.0 * np.pi * late * t + 1.0)
    y *= meseta(n, 0.05, 0.2)
    return normalizar(filtro(y, 150.0, 6000.0), -5.0)


def resoplido(i):
    """Un caballo que resopla: aire por los ollares, con el aleteo de los belfos, cada vez más lento."""
    r = np.random.default_rng(700 + i)
    dur = [0.8, 0.6][i % 2]
    n = int(dur * SR)
    t = np.arange(n) / SR
    aleteo = np.abs(np.sin(np.pi * np.cumsum(np.interp(t, [0.0, dur], [r.uniform(24.0, 28.0), 15.0])) / SR)) ** 1.4
    y = filtro(r.standard_normal(n), 250.0, 1900.0) * (0.3 + 0.7 * aleteo) * cae(n, dur * 0.36, 0.015)
    y += filtro(r.standard_normal(n), 1200.0, 3800.0) * cae(n, 0.05, 0.004) * 0.25
    return normalizar(cerrar(y, 2.0, 60.0), -6.0)


def cloqueo(i):
    """Una gallina: tres o cuatro "poc" cortos, el último un poco más alto."""
    r = np.random.default_rng(800 + i)
    cuantos = [3, 4, 5][i % 3]
    y = np.zeros(int(1.5 * SR))
    donde = 0.02
    for c in range(cuantos):
        ultimo = c == cuantos - 1
        dur = 0.16 if ultimo else r.uniform(0.085, 0.12)
        alto = r.uniform(520.0, 600.0) * (1.25 if ultimo else 1.0)
        poc = voz(dur, lambda u, alto=alto: alto * (0.68 + 0.32 * np.exp(-u * 4.0)), [(1150.0, 300.0, 1.0), (2600.0, 500.0, 0.6)], r, caida=0.9, temblor=0.02, aire=0.02)
        poc *= cae(poc.size, 0.05 if ultimo else 0.03, 0.006)
        sumar(y, poc / np.max(np.abs(poc)) * r.uniform(0.6, 1.0), int(donde * SR))
        donde += dur + r.uniform(0.1, 0.24)
    return normalizar(cerrar(y[:int((donde + 0.05) * SR)], 1.5, 30.0), -8.0)


def gallo():
    """El gallo al amanecer: tres notas cortas y una larga que se cae al final."""
    r = np.random.default_rng(900)
    notas = [(0.17, 610.0, 700.0), (0.13, 700.0, 760.0), (0.15, 720.0, 830.0), (0.95, 880.0, 520.0)]
    y = np.zeros(int(2.0 * SR))
    donde = 0.02
    for dur, f_ini, f_fin in notas:
        if dur > 0.5:
            tono = lambda u, a=f_ini, b=f_fin: np.interp(u, [0.0, 0.12, 0.6, 1.0], [a * 0.9, a, a * 0.97, b]) * (1.0 + 0.012 * np.sin(2.0 * np.pi * 6.0 * u * 0.95))
        else:
            tono = lambda u, a=f_ini, b=f_fin: a + (b - a) * u
        nota = voz(dur, tono, [(1250.0, 300.0, 1.0), (2500.0, 450.0, 0.8), (3700.0, 600.0, 0.4)], r, caida=0.8, temblor=0.012, ronquera=0.18, aire=0.03)
        nota *= meseta(nota.size, 0.02, 0.06 if dur < 0.5 else 0.3)
        sumar(y, nota / np.max(np.abs(nota)), int(donde * SR))
        donde += dur + 0.045
    return normalizar(cerrar(y[:int((donde + 0.05) * SR)], 1.5, 30.0), -6.0)


# ---------------------------------------------------------------- lo demás

def silbido():
    """Zenón silba a Ceniza: una nota que sube, se sostiene y remata con un golpe más alto."""
    r = np.random.default_rng(1000)
    n = int(0.95 * SR)
    t = np.arange(n) / SR
    tono = np.interp(t, [0.0, 0.2, 0.55, 0.62, 0.7, 0.86, 0.95], [1500.0, 2350.0, 2450.0, 2150.0, 3050.0, 3100.0, 2500.0])
    tono *= 1.0 + 0.006 * np.sin(2.0 * np.pi * 5.5 * t)
    fase = 2.0 * np.pi * np.cumsum(tono) / SR
    fuerza = np.interp(t, [0.0, 0.04, 0.5, 0.6, 0.64, 0.68, 0.88, 0.95], [0.0, 0.8, 1.0, 0.25, 0.2, 1.0, 0.9, 0.0])
    y = (np.sin(fase) + 0.05 * np.sin(2.0 * fase)) * fuerza
    y += filtro(r.standard_normal(n), 1800.0, 4500.0) * 0.05 * fuerza
    return normalizar(cerrar(y, 3.0, 20.0), -6.0)


def chingolo(i):
    """El canto del chingolo: dos o tres silbos claros y un trino corto al final."""
    r = np.random.default_rng(1100 + i)
    silbos = [
        [(0.22, 5200.0, 4200.0), (0.2, 3600.0, 5500.0), (0.24, 4600.0, 4550.0)],
        [(0.26, 4300.0, 5600.0), (0.22, 5300.0, 4000.0)],
        [(0.18, 5000.0, 4400.0), (0.2, 4400.0, 5200.0), (0.2, 5200.0, 4300.0)],
    ][i % 3]
    y = np.zeros(int(2.0 * SR))
    donde = 0.02

    def silbo(dur, f_ini, f_fin, fuerza):
        m = int(dur * SR)
        u = np.linspace(0.0, 1.0, m, endpoint=False)
        fase = 2.0 * np.pi * np.cumsum(f_ini + (f_fin - f_ini) * u) / SR
        return (np.sin(fase) + 0.03 * np.sin(2.0 * fase)) * np.sin(np.pi * u) ** 0.7 * fuerza

    for dur, f_ini, f_fin in silbos:
        sumar(y, silbo(dur, f_ini, f_fin, 1.0), int(donde * SR))
        donde += dur + r.uniform(0.05, 0.08)
    trino = r.uniform(4700.0, 5300.0)
    for k in range(int(r.integers(7, 11))):
        sumar(y, silbo(0.045, trino * 1.08, trino * 0.94, 0.9 - 0.06 * k), int(donde * SR))
        donde += 0.07
    return normalizar(cerrar(y[:int((donde + 0.03) * SR)], 2.0, 20.0), -8.0)


def hacha(i):
    """Un hachazo en leña seca: el golpe, la madera que suena y la astilla."""
    r = np.random.default_rng(1200 + i)
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    y = np.sin(2.0 * np.pi * r.uniform(250.0, 330.0) * t) * cae(n, 0.03, 0.0006) * 0.7
    y += np.sin(2.0 * np.pi * r.uniform(640.0, 820.0) * t) * cae(n, 0.014, 0.0005) * 0.4
    y += filtro(r.standard_normal(n), 700.0, 4200.0) * cae(n, 0.011, 0.0004) * 0.9
    y += filtro(r.standard_normal(n), 0.0, 220.0) * cae(n, 0.03) * 0.5
    return normalizar(cerrar(y), -5.0)


# ---------------------------------------------------------------- guardar

def guardar_wav(nombre, x):
    ruta = os.path.join(SALIDA, nombre + '.wav')
    _escribir_wav(ruta, x)
    return ruta


def _escribir_wav(ruta, x):
    x = np.clip(x, -1.0, 1.0)
    datos = (x * 32767.0).astype('<i2')
    with wave.open(ruta, 'wb') as w:
        w.setnchannels(1 if x.ndim == 1 else x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(datos.tobytes())


def guardar_ogg(nombre, x, calidad=5):
    """OGG para los largos (pesan diez veces menos). Pasa por un WAV temporal y por ffmpeg."""
    ruta = os.path.join(SALIDA, nombre + '.ogg')
    with tempfile.TemporaryDirectory() as tmp:
        crudo = os.path.join(tmp, nombre + '.wav')
        _escribir_wav(crudo, x)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', crudo, '-c:a', 'libvorbis', '-q:a', str(calidad), ruta], check=True)
    return ruta


def main():
    solo = sys.argv[1] if len(sys.argv) > 1 else ''
    os.makedirs(SALIDA, exist_ok=True)
    cascos = [casco(i) for i in range(6)]
    cortos = {}
    for i in range(5):
        cortos['paso_%d' % (i + 1)] = lambda i=i: paso(i)
    for i in range(4):
        cortos['paso_ripio_%d' % (i + 1)] = lambda i=i: paso_ripio(i)
        cortos['paso_agua_%d' % (i + 1)] = lambda i=i: paso_agua(i)
    for i in range(6):
        cortos['casco_%d' % (i + 1)] = lambda i=i: cascos[i]
    for i in range(3):
        cortos['mugido_%d' % (i + 1)] = lambda i=i: mugido(i)
        cortos['balido_%d' % (i + 1)] = lambda i=i: balido(i)
        cortos['cloqueo_%d' % (i + 1)] = lambda i=i: cloqueo(i)
        cortos['chingolo_%d' % (i + 1)] = lambda i=i: chingolo(i)
    for i in range(2):
        cortos['resoplido_%d' % (i + 1)] = lambda i=i: resoplido(i)
        cortos['hacha_%d' % (i + 1)] = lambda i=i: hacha(i)
    cortos['gallo'] = gallo
    cortos['silbido'] = silbido
    largos = {'viento': viento, 'fuego': fuego, 'tropel': lambda: tropel(cascos), 'grillos': grillos, 'rio': rio}
    for nombre, receta in cortos.items():
        if nombre.startswith(solo):
            ruta = guardar_wav(nombre, receta())
            print('%-16s %6.1f KB' % (os.path.basename(ruta), os.path.getsize(ruta) / 1024.0))
    for nombre, receta in largos.items():
        if nombre.startswith(solo):
            ruta = guardar_ogg(nombre, receta())
            print('%-16s %6.1f KB' % (os.path.basename(ruta), os.path.getsize(ruta) / 1024.0))


if __name__ == '__main__':
    main()
