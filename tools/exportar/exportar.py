# -*- coding: utf-8 -*-
"""Arma la versión para Windows de El Gaucho Zenón (tanda 9).

    py tools/exportar/exportar.py             exporta con las plantillas de Godot (tienen que estar instaladas)
    py tools/exportar/exportar.py --depuracion  la misma, con el ejecutable de depuración: es el que
                                              acepta programas de prueba (tools/exportar/probar_exe.gd)
    py tools/exportar/exportar.py --prueba    arma una versión de prueba con el ejecutable del editor
                                              (no hacen falta plantillas; pesa más y no es para pasar)

Qué hace:
  1. Copia el proyecto a una carpeta de armado, al lado de la del proyecto, sin lo que no es del
     juego: notas, fotos de referencia, fuentes de Blender, herramientas y lo del asistente.
  2. En esa copia le saca a project.godot el plugin godot_mcp (con sus tres autoloads) y el de
     AmbientCG. El proyecto de verdad no se toca.
  3. Corre Godot sin ventana sobre la copia y exporta el perfil "Windows" de export_presets.cfg.
  4. Escribe LEEME.txt y LICENCIAS.txt al lado del .exe.

Por qué desde una copia: el editor suele estar abierto con las herramientas del asistente
conectadas, y exportar arranca un segundo editor; sobre la misma carpeta se pisarían. Y así la
versión exportada sale igual la haga quien la haga.

La carpeta de salida es ../exportado/GauchoZenon-v<versión>/ (fuera del proyecto y de git).
El ejecutable de Godot se toma de la variable GODOT o del lugar de siempre en esta compu.
"""
import os
import re
import shutil
import subprocess
import sys

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
AFUERA = os.path.normpath(os.path.join(RAIZ, '..', 'exportado'))
ARMADO = os.path.join(AFUERA, '_armado')
GODOT = os.environ.get('GODOT', r'G:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')

# Carpetas y archivos que no van a la copia (lo que no es del juego).
CARPETAS_AFUERA = ['.git', '.revision', '.claude', '.cursor', 'docs', 'referencias', 'art_source', 'tools',
                   'graphify-out', 'AmbientCG', '__pycache__',
                   os.path.join('addons', 'godot_mcp'), os.path.join('addons', 'ambientcg'),
                   os.path.join('addons', 'zylann.hterrain', 'doc'),
                   os.path.join('audio', 'musica', 'afuera_por_ahora'),
                   os.path.join('assets', 'personajes', 'animaciones'), os.path.join('assets', 'personajes', 'mixamo'),
                   os.path.join('.godot', 'editor'), os.path.join('.godot', 'shader_cache'), os.path.join('.godot', 'exported')]
ARCHIVOS_AFUERA = ['*.blend', '*.blend1', '*.md', '*.mdc', '*.fbx', '*.avi', '*.zip', '.env', 'API_KEYS.md', '.mcp.json',
                   'acgicon.png', 'acgicon.png.import', 'LICENSE']


def version():
    texto = open(os.path.join(RAIZ, 'project.godot'), encoding='utf-8').read()
    hallada = re.search(r'^config/version="([^"]*)"', texto, re.M)
    return hallada.group(1) if hallada else '0'


def copiar():
    """Deja la carpeta de armado igual al proyecto (menos lo que no va). La segunda vez solo copia lo que cambió."""
    os.makedirs(ARMADO, exist_ok=True)
    orden = ['robocopy', RAIZ, ARMADO, '/MIR', '/NFL', '/NDL', '/NJH', '/NP', '/R:1', '/W:1', '/XD']
    # Con la ruta entera, para sacar esa carpeta y no otra que se llame igual; "__pycache__", donde esté.
    orden += [c if c == '__pycache__' else os.path.join(RAIZ, c) for c in CARPETAS_AFUERA]
    orden += ['/XF'] + ARCHIVOS_AFUERA
    codigo = subprocess.run(orden).returncode
    if codigo >= 8:  # robocopy: de 0 a 7 es que anduvo
        sys.exit('La copia falló (robocopy devolvió %d).' % codigo)


def limpiar_proyecto():
    """En la copia: sin el plugin del asistente, sin sus autoloads y sin el de AmbientCG."""
    ruta = os.path.join(ARMADO, 'project.godot')
    lineas = open(ruta, encoding='utf-8').read().split('\n')
    limpio = []
    for linea in lineas:
        if re.match(r'^MCP\w+="\*res://addons/godot_mcp/', linea):
            continue
        if linea.startswith('enabled=PackedStringArray('):
            quedan = [p for p in re.findall(r'"([^"]+)"', linea) if 'godot_mcp' not in p and 'ambientcg' not in p]
            linea = 'enabled=PackedStringArray(%s)' % ', '.join('"%s"' % p for p in quedan)
        limpio.append(linea)
    if any('godot_mcp' in linea for linea in limpio):
        sys.exit('En la copia de project.godot quedó algo de godot_mcp: revisá limpiar_proyecto().')
    open(ruta, 'w', encoding='utf-8', newline='\n').write('\n'.join(limpio))


def godot(*argumentos, registro):
    orden = [GODOT, '--headless', '--path', ARMADO] + list(argumentos)
    with open(registro, 'w', encoding='utf-8', errors='replace') as salida:
        return subprocess.run(orden, stdout=salida, stderr=subprocess.STDOUT).returncode


def plantillas_instaladas():
    carpeta = os.path.join(os.environ.get('APPDATA', ''), 'Godot', 'export_templates')
    if not os.path.isdir(carpeta):
        return False
    return any(os.path.exists(os.path.join(carpeta, v, 'windows_release_x86_64.exe')) for v in os.listdir(carpeta))


def escribir_leeme(salida, de_prueba):
    aviso = ''
    if de_prueba:
        aviso = ('ESTA ES UNA VERSIÓN DE PRUEBA: usa el ejecutable del editor de Godot en lugar del del\n'
                 'juego. Se juega igual, pero pesa más. La versión para pasar se arma con las plantillas\n'
                 'de exportación de Godot instaladas (ver tools/exportar/LEEME.md en el proyecto).\n\n')
    texto = '''El Gaucho Zenón - versión %s
==============================

%sNorte de la Patagonia, 1881. Zenón es un baqueano que debe ciento ochenta patacones en la
pulpería de Don Ceferino. La línea del ejército viene llegando al Nahuel Huapi, y cada uno
(el sargento del fortín, el estanciero, la gente de la toldería) tiene algo que pedirle.

CÓMO SE JUEGA
  Abrí GauchoZenon.exe. No hace falta instalar nada.
  GauchoZenon.exe y GauchoZenon.pck tienen que quedar juntos, en la misma carpeta.

  WASD        andar                  Shift     correr
  Mouse       mirar                  Rueda     acercar o alejar la cámara
  E           usar y hablar          Espacio   saltar
  Tab         acordarte adónde ir    Esc       pausa (ajustes, guardar, salir)
  F11         pantalla completa

  A caballo: arrimado a Ceniza, E la monta. W anda al paso, Shift sube de marcha (trote,
  galope), S sofrena, A y D tuercen el rumbo, Q se baja. A pie, Q la silba y viene.

  En un diálogo: E o Enter para seguir; los números o el mouse para elegir.

SI ANDA LENTO
  Esc, Ajustes, "Imagen: liviana". Dibuja la imagen más chica, con sombras más cortas y menos
  pasto. Necesita una placa de video que soporte Vulkan (cualquiera de los últimos años).

LA PARTIDA
  Se guarda sola: al cerrar un diálogo, al sentarse al fogón, al salir por el menú de pausa
  y al cerrar la ventana. Queda en:
      %%APPDATA%%\\Godot\\app_userdata\\GauchoZenonRPG\\partida.json
  Los ajustes quedan en ajustes.cfg, en la misma carpeta. Si algo falla, el registro de la
  última vez que se abrió el juego está ahí mismo, en logs\\godot.log.

SI WINDOWS AVISA
  El programa no está firmado. Windows puede mostrar "Windows protegió su PC": se entra por
  "Más información" y "Ejecutar de todas formas".

CRÉDITOS
  Juego: Willy.
  Música: Mariano Amir Jatip, del álbum "Nothofagus".
  Hecho con Godot Engine (godotengine.org). Las licencias del motor y de las piezas de terceros
  que usa están en LICENCIAS.txt. El terreno usa el plugin HTerrain, de Marc Gilleron.
  Los sonidos de ambiente están generados por programa; ninguno es una grabación.
''' % (version(), aviso)
    open(os.path.join(salida, 'LEEME.txt'), 'w', encoding='utf-8-sig', newline='\r\n').write(texto)


def main():
    de_prueba = '--prueba' in sys.argv
    depuracion = '--depuracion' in sys.argv
    if not os.path.exists(GODOT):
        sys.exit('No encuentro Godot en %s. Poné su ruta en la variable GODOT.' % GODOT)
    if not de_prueba and not plantillas_instaladas():
        sys.exit('Faltan las plantillas de exportación de Godot (Editor > Administrar plantillas de exportación).\n'
                 'Sin ellas se puede armar una versión de prueba: py tools/exportar/exportar.py --prueba')
    salida = os.path.join(AFUERA, 'GauchoZenon-v%s%s' % (version(), '-prueba' if de_prueba else ('-depuracion' if depuracion else '')))
    print('1. Copiando el proyecto a %s ...' % ARMADO)
    copiar()
    limpiar_proyecto()
    if os.path.isdir(salida):
        try:
            shutil.rmtree(salida)
        except PermissionError:
            sys.exit('No pude borrar %s. Cerrá el juego exportado (o lo que tenga abierta esa carpeta) y volvé a correr.' % salida)
    os.makedirs(salida)
    registro = os.path.join(AFUERA, 'exportar.log')
    if de_prueba:
        print('2. Empaquetando (versión de prueba, con el ejecutable del editor) ...')
        codigo = godot('--export-pack', 'Windows', os.path.join(salida, 'GauchoZenon.pck'), registro=registro)
        shutil.copy2(GODOT.replace('_console.exe', '.exe'), os.path.join(salida, 'GauchoZenon.exe'))
    else:
        print('2. Exportando con las plantillas de Godot ...')
        codigo = godot('--export-debug' if depuracion else '--export-release', 'Windows', os.path.join(salida, 'GauchoZenon.exe'), registro=registro)
    falta = [n for n in ('GauchoZenon.exe', 'GauchoZenon.pck') if not os.path.exists(os.path.join(salida, n))]
    if falta:
        sys.exit('La exportación no dejó %s (Godot devolvió %d). Mirá %s' % (' ni '.join(falta), codigo, registro))
    print('3. Escribiendo LEEME.txt y LICENCIAS.txt ...')
    escribir_leeme(salida, de_prueba)
    subprocess.run([GODOT, '--headless', '--path', RAIZ, '--script', 'res://tools/exportar/licencias.gd', '--',
                    '--salida=' + os.path.join(salida, 'LICENCIAS.txt')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(os.path.join(salida, 'LICENCIAS.txt')):
        sys.exit('No se escribió LICENCIAS.txt: sin ese archivo no se puede pasar el juego.')
    print('\nListo: %s' % salida)
    total = 0
    for nombre in sorted(os.listdir(salida)):
        peso = os.path.getsize(os.path.join(salida, nombre))
        total += peso
        print('  %-28s %8.1f MB' % (nombre, peso / 1048576.0))
    print('  %-28s %8.1f MB' % ('en total', total / 1048576.0))
    errores = [l for l in open(registro, encoding='utf-8', errors='replace') if 'ERROR' in l]
    print('El registro de Godot (%s) tiene %d líneas con ERROR.' % (registro, len(errores)))


if __name__ == '__main__':
    main()
