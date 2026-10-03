# Corre Hunyuan3D local por tandas de dos modelos, reiniciando el servidor entre tandas.
# Uso: py hunyuan_tanda.py <carpeta con PNG recortados> nombre1 nombre2 ...
import sys, os, time, json, base64, subprocess, urllib.request, urllib.error
RAIZ = r'G:\Hunyuan3D2_WinPortable'
URL = 'http://127.0.0.1:8081'
carpeta = sys.argv[1]
os.makedirs(carpeta, exist_ok=True)
nombres = sys.argv[2:]
ESPERA_MODELO = 8 * 60
POR_TANDA = 1          # con dos por tanda, el segundo desbordo la placa (24 GB) el 3 de octubre

def log(*a):
    print(time.strftime('%H:%M:%S'), *a, flush=True)

def pedir(ruta, datos=None, espera=30):
    req = urllib.request.Request(URL + ruta, data=json.dumps(datos).encode() if datos is not None else None,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=espera) as r:
        return json.loads(r.read().decode())

def gpu():
    try:
        return subprocess.run(['nvidia-smi', '--query-gpu=memory.used', '--format=csv,noheader'],
                              capture_output=True, text=True).stdout.strip()
    except Exception:
        return '?'

def lanzar():
    env = dict(os.environ, HF_HUB_CACHE=RAIZ + r'\HuggingFaceHub', HY3DGEN_MODELS=RAIZ + r'\HuggingFaceHub')
    salida = open(os.path.join(carpeta, 'servidor.log'), 'ab')
    p = subprocess.Popen([RAIZ + r'\python_standalone\python.exe', '-s', 'api_server.py', '--low_vram_mode',
                          '--model_path', 'tencent/Hunyuan3D-2.1', '--subfolder', 'hunyuan3d-dit-v2-1',
                          '--host', '127.0.0.1', '--port', '8081'],
                         cwd=RAIZ + r'\Hunyuan3D-2.1', env=env, stdout=salida, stderr=subprocess.STDOUT)
    log('servidor lanzado, pid', p.pid)
    t0 = time.time()
    while time.time() - t0 < 720:
        if p.poll() is not None:
            log('el servidor se cerro solo, codigo', p.returncode); return None
        try:
            pedir('/health', espera=5); log('servidor listo en %.0f s, gpu %s' % (time.time() - t0, gpu())); return p
        except Exception:
            time.sleep(5)
    log('el servidor no respondio en 12 minutos'); matar(p); return None

def matar(p):
    if p is None: return
    subprocess.run(['taskkill', '/PID', str(p.pid), '/T', '/F'], capture_output=True)
    time.sleep(6)
    log('servidor cerrado, gpu', gpu())

def generar(nombre):
    with open(os.path.join(carpeta, nombre + '.png'), 'rb') as f:
        imagen = base64.b64encode(f.read()).decode()
    uid = pedir('/send', {'image': imagen, 'remove_background': False, 'texture': True})['uid']
    log(nombre, 'enviado', uid)
    t0 = time.time(); ultimo = ''; llena = 0
    while time.time() - t0 < ESPERA_MODELO:
        time.sleep(10)
        try:
            r = pedir('/status/' + uid, espera=120)
        except Exception as e:
            log(nombre, 'sin respuesta:', e); continue
        if r.get('status') != ultimo:
            ultimo = r.get('status'); log(nombre, 'estado', ultimo, '%.0f s' % (time.time() - t0), 'gpu', gpu())
        try:
            llena = llena + 1 if int(gpu().split()[0]) > 23600 else 0
        except Exception:
            llena = 0
        if llena >= 6:          # un minuto con la placa llena: desbordo a memoria compartida, no termina mas
            log(nombre, 'PLACA LLENA durante un minuto en', ultimo, '-> se corta'); return False
        if ultimo == 'completed':
            destino = os.path.join(carpeta, nombre + '_hy.glb')
            with open(destino, 'wb') as f:
                f.write(base64.b64decode(r['model_base64']))
            log(nombre, 'LISTO', os.path.getsize(destino) // 1024, 'KB en %.0f s' % (time.time() - t0)); return True
        if ultimo == 'error':
            log(nombre, 'ERROR', r.get('message')); return False
    log(nombre, 'COLGADO en', ultimo, 'tras', ESPERA_MODELO, 's'); return False

pendientes = [n for n in nombres if not os.path.exists(os.path.join(carpeta, n + '_hy.glb'))]
intentos = {n: 0 for n in pendientes}
servidor = None; hechos_en_tanda = 0
while pendientes:
    n = pendientes[0]
    if servidor is None or hechos_en_tanda >= POR_TANDA:
        matar(servidor); servidor = lanzar(); hechos_en_tanda = 0
        if servidor is None:
            log('BLOQUEO: no se pudo lanzar Hunyuan'); break
    intentos[n] += 1
    ok = generar(n)
    hechos_en_tanda += 1
    if ok:
        pendientes.pop(0)
    else:
        matar(servidor); servidor = None
        if intentos[n] >= 2:
            log('BLOQUEO:', n, 'fallo dos veces, se saltea'); pendientes.pop(0)
matar(servidor)
log('FIN. hechos:', [n for n in nombres if os.path.exists(os.path.join(carpeta, n + '_hy.glb'))],
    '| faltan:', [n for n in nombres if not os.path.exists(os.path.join(carpeta, n + '_hy.glb'))])
