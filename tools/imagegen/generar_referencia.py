#!/usr/bin/env python3
"""
Genera imagenes de referencia para Hunyuan3D (Gaucho Zenon) por API.

Pensado para que lo use Claude/Cursor: si falta la imagen de un asset, se genera
con el estilo de la direccion de arte (estilo_zenon.json) y queda en
art_source/referencias_generadas/<categoria>/<nombre>.png. La carpeta art_source/
lleva un .gdignore para que Godot no importe esas imagenes.

Ejemplos:
  python tools/imagegen/generar_referencia.py --existe --categoria humano --nombre peon_01
  python tools/imagegen/generar_referencia.py --categoria humano --nombre peon_01 \
      --sujeto "army sergeant in his 40s, worn grey-blue wool tunic, kepi, trimmed moustache"
  python tools/imagegen/generar_referencia.py --categoria animal --nombre guanaco_01 \
      --sujeto "adult guanaco" --foto fotos/guanaco.jpg
  python tools/imagegen/generar_referencia.py ... --dry-run     # solo muestra el prompt, no gasta

Claves (nunca se imprimen): variables de entorno, o archivo .env, o API_KEYS.md
en la raiz del repo, con lineas del tipo  GEMINI_API_KEY=...  /  FAL_KEY=...
"""
import argparse
import base64
import csv
import json
import mimetypes
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import requests

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parents[1]  # tools/imagegen/ -> raiz del repo
ESTILO = json.loads((AQUI / "estilo_zenon.json").read_text(encoding="utf-8"))

DIR_SALIDA = Path(os.environ.get("ZENON_REFS_DIR", RAIZ / "art_source" / "referencias_generadas"))
REF_ESTILO = Path(os.environ.get("ZENON_STYLE_REF", RAIZ / "referencias" / "Zenon.png"))
MODELO_GEMINI = os.environ.get("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
ENDPOINT_FAL = os.environ.get("FAL_IMAGE_ENDPOINT", "fal-ai/nano-banana")

# USD aproximados por imagen (1K). Solo para el registro de gasto; verificar en el panel del proveedor.
PRECIOS = {
    "gemini-2.5-flash-image": 0.039,
    "gemini-3.1-flash-image": 0.067,
    "gemini-3-pro-image": 0.134,
}
PRECIO_DEFECTO = 0.07
MAX_SIN_CONFIRMAR = 4  # imagenes por ejecucion sin --yes


# ----------------------------------------------------------------- claves
def cargar_claves():
    """Lee KEY=VALUE de .env y API_KEYS.md. Las variables de entorno tienen prioridad."""
    claves = {}
    for nombre in (".env", "API_KEYS.md"):
        ruta = RAIZ / nombre
        if not ruta.is_file():
            continue
        for linea in ruta.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = re.match(r"^\s*`?([A-Z][A-Z0-9_]*)\s*=\s*['\"]?([^'\"`\s]+)['\"]?`?\s*$", linea)
            if m:
                claves.setdefault(m.group(1), m.group(2))
    for k in ("GEMINI_API_KEY", "FAL_KEY"):
        if os.environ.get(k):
            claves[k] = os.environ[k]
    return claves


def clave(claves, nombre):
    valor = claves.get(nombre)
    if not valor or valor.startswith("PEGAR_"):
        sys.exit(f"Falta {nombre}. Cargala en .env o API_KEYS.md (ver .env.example).")
    return valor


# ----------------------------------------------------------------- prompt
def armar_prompt(args, hay_ref_estilo, hay_fotos):
    cat = ESTILO["categorias"][args.categoria]
    pose = args.pose or cat["pose_default"]
    if pose in ESTILO["poses"]:
        bloque_pose = ESTILO["poses"][pose]
    else:
        bloque_pose = ESTILO["poses_extra"].get(pose, "")

    partes = []
    if hay_ref_estilo:
        partes.append(
            "The first reference image shows the target art style, materials and rendering. "
            "Match that style only; do NOT copy its character, face, pose or background."
        )
    if hay_fotos:
        partes.append(
            "The following reference photo(s) are for anatomy, clothing and historical details only. "
            "Re-draw the subject in the target art style, do not keep the photographic look."
        )
    partes.append(ESTILO["estilo"])
    partes.append(f"Subject: {args.sujeto}.")
    partes.append(cat["extra"])
    if args.categoria == "humano":
        partes.append("This is a NEW individual, clearly different from any other character: own face, age, build and hair. Do not default to a dark poncho, a beard or a red neckerchief unless the subject says so.")
    if args.variante:
        partes.append(f"Variation: {args.variante}.")
    if bloque_pose:
        partes.append(bloque_pose)
    if args.escena:
        partes.append(ESTILO["fondo_escena"])
        partes.append("Full body, entire subject in frame.")
    else:
        partes.append(ESTILO["fondo_hunyuan"])
    partes.append(ESTILO["evitar"])
    return "\n".join(p for p in partes if p)


def a_data(ruta):
    mime = mimetypes.guess_type(str(ruta))[0] or "image/png"
    return mime, base64.b64encode(Path(ruta).read_bytes()).decode()


# ----------------------------------------------------------------- Gemini
def generar_gemini(claves, prompt, imagenes, modelo, aspecto):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent"
    partes = [{"text": prompt}]
    for ruta in imagenes:
        mime, datos = a_data(ruta)
        partes.append({"inline_data": {"mime_type": mime, "data": datos}})
    cuerpo = {
        "contents": [{"parts": partes}],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {"aspectRatio": aspecto},
        },
    }
    r = requests.post(
        url,
        headers={"x-goog-api-key": clave(claves, "GEMINI_API_KEY"), "Content-Type": "application/json"},
        json=cuerpo,
        timeout=180,
    )
    if r.status_code != 200:
        sys.exit(f"Gemini devolvio {r.status_code}: {r.text[:600]}")
    datos = r.json()
    textos = []
    for cand in datos.get("candidates", []):
        for p in cand.get("content", {}).get("parts", []):
            blob = p.get("inlineData") or p.get("inline_data")
            if blob and blob.get("data"):
                return base64.b64decode(blob["data"])
            if p.get("text"):
                textos.append(p["text"])
    motivo = datos.get("promptFeedback") or [c.get("finishReason") for c in datos.get("candidates", [])]
    sys.exit(f"Gemini no devolvio imagen. Motivo: {motivo} {' '.join(textos)[:300]}")


# ----------------------------------------------------------------- fal.ai (sin probar con clave real)
def generar_fal(claves, prompt, imagenes, endpoint, aspecto):
    cab = {"Authorization": f"Key {clave(claves, 'FAL_KEY')}", "Content-Type": "application/json"}
    cuerpo = {"prompt": prompt, "num_images": 1, "aspect_ratio": aspecto, "output_format": "png"}
    if imagenes:
        endpoint = endpoint.rstrip("/") + "/edit" if not endpoint.endswith("/edit") else endpoint
        cuerpo["image_urls"] = ["data:%s;base64,%s" % a_data(p) for p in imagenes]
    r = requests.post(f"https://queue.fal.run/{endpoint}", headers=cab, json=cuerpo, timeout=60)
    if r.status_code not in (200, 201):
        sys.exit(f"fal devolvio {r.status_code}: {r.text[:600]}")
    job = r.json()
    for _ in range(90):
        time.sleep(2)
        st = requests.get(job["status_url"], headers=cab, timeout=30).json()
        if st.get("status") == "COMPLETED":
            res = requests.get(job["response_url"], headers=cab, timeout=60).json()
            return requests.get(res["images"][0]["url"], timeout=120).content
        if st.get("status") in ("FAILED", "ERROR"):
            sys.exit(f"fal fallo: {st}")
    sys.exit("fal: tiempo agotado esperando la imagen.")


# ----------------------------------------------------------------- registro de gasto
def registrar(backend, modelo, categoria, nombre, ruta):
    precio = PRECIOS.get(modelo, PRECIO_DEFECTO)
    log = DIR_SALIDA / "costos.csv"
    nuevo = not log.exists()
    with log.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if nuevo:
            w.writerow(["fecha", "backend", "modelo", "categoria", "nombre", "usd_estimado", "archivo"])
        w.writerow([datetime.now().isoformat(timespec="seconds"), backend, modelo, categoria, nombre, precio, ruta.name])
    total = 0.0
    with log.open(encoding="utf-8") as f:
        next(f, None)
        for fila in csv.reader(f):
            try:
                total += float(fila[5])
            except (IndexError, ValueError):
                pass
    return precio, total


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--categoria", required=True, choices=list(ESTILO["categorias"]))
    ap.add_argument("--nombre", required=True, help="slug del asset, ej: peon_01 (sin espacios)")
    ap.add_argument("--sujeto", help="descripcion del sujeto, en ingles")
    ap.add_argument("--variante", help="variacion: color de pelaje, tamano, ropa, etc.")
    ap.add_argument("--pose", help="tpose | neutral | animal | ninguna (por defecto segun categoria)")
    ap.add_argument("--foto", nargs="*", default=[], help="fotos reales de referencia (no se suben al repo)")
    ap.add_argument("--estilo-ref", action="store_true", help="adjuntar referencias/Zenon.png como referencia de estilo (sirve para props/animales; en personajes tiende a copiar a Zenon)")
    ap.add_argument("--escena", action="store_true", help="fondo de estepa/cordillera en vez de fondo liso")
    ap.add_argument("--backend", choices=["gemini", "fal"], default="gemini")
    ap.add_argument("--model", help="modelo de Gemini o endpoint de fal")
    ap.add_argument("--n", type=int, default=1, help="cantidad de variantes (genera nombre_v1, _v2...)")
    ap.add_argument("--force", action="store_true", help="regenerar aunque exista")
    ap.add_argument("--yes", action="store_true", help=f"permitir mas de {MAX_SIN_CONFIRMAR} imagenes")
    ap.add_argument("--existe", action="store_true", help="solo comprueba si ya existe (no gasta)")
    ap.add_argument("--dry-run", action="store_true", help="muestra el prompt y sale (no gasta)")
    args = ap.parse_args()

    if not re.fullmatch(r"[a-z0-9_\-]+", args.nombre):
        sys.exit("--nombre: solo minusculas, numeros, _ y -")

    nombres = [args.nombre] if args.n == 1 else [f"{args.nombre}_v{i}" for i in range(1, args.n + 1)]
    carpeta = DIR_SALIDA / args.categoria
    salidas = [carpeta / f"{n}.png" for n in nombres]

    if args.existe:
        faltan = [s for s in salidas if not s.exists()]
        for s in salidas:
            print(("EXISTE " if s.exists() else "FALTA  ") + str(s.relative_to(RAIZ)))
        sys.exit(1 if faltan else 0)

    if not args.sujeto:
        sys.exit("--sujeto es obligatorio para generar.")
    if args.n > MAX_SIN_CONFIRMAR and not args.yes:
        sys.exit(f"{args.n} imagenes: agregar --yes para confirmar el gasto.")

    imagenes = []
    hay_ref_estilo = args.estilo_ref and REF_ESTILO.is_file()
    if hay_ref_estilo:
        imagenes.append(REF_ESTILO)
    fotos = [Path(f) for f in args.foto]
    for f in fotos:
        if not f.is_file():
            sys.exit(f"No existe la foto: {f}")
    imagenes += fotos

    prompt = armar_prompt(args, hay_ref_estilo, bool(fotos))
    aspecto = ESTILO["categorias"][args.categoria]["aspect_ratio"]
    modelo = args.model or (MODELO_GEMINI if args.backend == "gemini" else ENDPOINT_FAL)

    if args.dry_run:
        print(f"[backend={args.backend} modelo={modelo} aspecto={aspecto} adjuntos={[p.name for p in imagenes]}]\n")
        print(prompt)
        return

    claves = cargar_claves()
    carpeta.mkdir(parents=True, exist_ok=True)
    for nombre, salida in zip(nombres, salidas):
        if salida.exists() and not args.force:
            print(f"Ya existe, no se regenera: {salida.relative_to(RAIZ)}")
            continue
        if args.backend == "gemini":
            png = generar_gemini(claves, prompt, imagenes, modelo, aspecto)
        else:
            png = generar_fal(claves, prompt, imagenes, modelo, aspecto)
        salida.write_bytes(png)
        salida.with_suffix(".prompt.txt").write_text(prompt, encoding="utf-8")
        precio, total = registrar(args.backend, modelo, args.categoria, nombre, salida)
        print(f"OK {salida.relative_to(RAIZ)}  (~{precio:.3f} USD; acumulado estimado {total:.2f} USD)")


if __name__ == "__main__":
    main()
