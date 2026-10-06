# -*- coding: utf-8 -*-
"""Mide y dibuja los sonidos de audio/ambiente/, para revisarlos sin oírlos.

    py tools/sonido/ver.py                 todos
    py tools/sonido/ver.py casco mugido    solo los que empiezan con esos nombres

De cada archivo dice cuánto dura, su pico y su nivel medio (en dB bajo el máximo), dónde está el
centro de su espectro y, en los que se repiten, si el empalme del final con el principio hace clic
("salto": el escalón entre la última muestra y la primera, contra el escalón típico entre dos
muestras seguidas; cerca de 1 es que no se nota). Además arma hojas con el espectro dibujado
(el tiempo hacia la derecha, los agudos arriba) en .revision/sonido/.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, '..', '..'))
ENTRADA = os.path.join(RAIZ, 'audio', 'ambiente')
SALIDA = os.path.join(RAIZ, '.revision', 'sonido')


def leer(ruta):
    """Devuelve (muestras entre -1 y 1, con una columna por canal, y frecuencia de muestreo)."""
    if ruta.endswith('.ogg'):
        with tempfile.TemporaryDirectory() as tmp:
            crudo = os.path.join(tmp, 'x.wav')
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', ruta, '-c:a', 'pcm_s16le', crudo], check=True)
            return leer(crudo)
    with wave.open(ruta, 'rb') as w:
        datos = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float64) / 32768.0
        return datos.reshape(-1, w.getnchannels()), w.getframerate()


def medir(x, sr, se_repite):
    mono = x.mean(axis=1)
    pico = 20.0 * np.log10(np.max(np.abs(x)) + 1e-12)
    medio = 20.0 * np.log10(np.sqrt(np.mean(mono ** 2)) + 1e-12)
    espectro = np.abs(np.fft.rfft(mono)) ** 2
    f = np.fft.rfftfreq(mono.size, 1.0 / sr)
    centro = float(np.sum(f * espectro) / (np.sum(espectro) + 1e-12))
    acumulado = np.cumsum(espectro) / (np.sum(espectro) + 1e-12)
    f90 = float(f[np.searchsorted(acumulado, 0.9)])
    fila = '%6.2f s  pico %6.1f dB  medio %6.1f dB  centro %5.0f Hz  90%% bajo %5.0f Hz' % (mono.size / sr, pico, medio, centro, f90)
    if se_repite:
        pasos = np.abs(np.diff(mono))
        salto = abs(mono[0] - mono[-1]) / (np.sqrt(np.mean(pasos ** 2)) + 1e-12)
        fila += '  salto %.2f' % salto
    return fila


def hoja(nombre, piezas):
    filas = (len(piezas) + 2) // 3
    fig, ejes = plt.subplots(filas, 3, figsize=(18, 3.6 * filas), squeeze=False)
    for eje in ejes.flat:
        eje.axis('off')
    for eje, (titulo, x, sr, se_repite) in zip(ejes.flat, piezas):
        eje.axis('on')
        mono = x.mean(axis=1)
        if se_repite:
            # Dos vueltas pegadas: si el empalme hiciera clic, se vería una raya vertical en el medio.
            mono = np.concatenate([mono[-sr * 2:], mono[:sr * 2]])
            titulo += ' (empalme al medio)'
        ventana = 1024 if mono.size > sr else 256
        eje.specgram(mono, NFFT=ventana, Fs=sr, noverlap=ventana * 3 // 4, cmap='magma', vmin=-110, vmax=-30)
        eje.set_ylim(0, 9000)
        eje.set_title(titulo, fontsize=10)
        linea = eje.twinx()
        t = np.arange(mono.size) / sr
        linea.plot(t, mono, color='white', linewidth=0.3, alpha=0.6)
        linea.set_ylim(-3, 1)
        linea.axis('off')
    fig.tight_layout()
    os.makedirs(SALIDA, exist_ok=True)
    ruta = os.path.join(SALIDA, 'hoja_%s.png' % nombre)
    fig.savefig(ruta, dpi=70)
    plt.close(fig)
    return ruta


def main():
    pedidos = sys.argv[1:]
    archivos = sorted(a for a in os.listdir(ENTRADA) if a.endswith(('.wav', '.ogg')))
    if pedidos:
        archivos = [a for a in archivos if any(a.startswith(p) for p in pedidos)]
    familias = {}
    for archivo in archivos:
        x, sr = leer(os.path.join(ENTRADA, archivo))
        se_repite = archivo.endswith('.ogg')
        print('%-18s %s' % (archivo, medir(x, sr, se_repite)))
        familia = 'largos' if se_repite else archivo.rsplit('.', 1)[0].rstrip('0123456789').rstrip('_').split('_')[0]
        familias.setdefault(familia, []).append((archivo, x, sr, se_repite))
    # Las familias de pocos archivos van juntas en una hoja.
    sueltas = []
    for familia in sorted(familias):
        if len(familias[familia]) <= 2 and familia != 'largos':
            sueltas += familias.pop(familia)
    if sueltas:
        familias['varios'] = sueltas
    for familia in sorted(familias):
        print('hoja:', hoja(familia, familias[familia]))


if __name__ == '__main__':
    main()
