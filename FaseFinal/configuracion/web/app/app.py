"""Portal de gestiones de Zenite Prestige Guatemala (prototipo academico, solo datos ficticios)."""
import os
import re
import secrets
import sqlite3
from datetime import datetime, timezone

from flask import Flask, render_template, request

DB_PATH = os.environ.get("ZENITE_DB", "/var/lib/zenite-portal/gestiones.db")
ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # sin I, O, 0 ni 1 para evitar confusiones
TIPOS = {"cotizacion": "Solicitud de cotización", "prueba": "Prueba de manejo"}
VEHICULOS = {
    "ZP-001": {"nombre": "Clase C 200", "marca": "Mercedes-Benz", "tipo": "Sedán", "anio": 2025, "motor": "Gasolina"},
    "ZP-003": {"nombre": "Macan", "marca": "Porsche", "tipo": "SUV", "anio": 2024, "motor": "Gasolina"},
    "ZP-005": {"nombre": "320i", "marca": "BMW", "tipo": "Sedán", "anio": 2024, "motor": "Gasolina"},
}
RE_CODIGO = re.compile(r"^ZP-[A-HJ-NP-Z2-9]{8}$")
RE_CORREO = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,120}\.[^@\s]{2,}$")
CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8192


def conectar():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def iniciar_db():
    with conectar() as con:
        con.execute(
            "CREATE TABLE IF NOT EXISTS gestiones ("
            "codigo TEXT PRIMARY KEY, tipo TEXT NOT NULL, vehiculo TEXT NOT NULL, nombre TEXT NOT NULL, "
            "correo TEXT NOT NULL, mensaje TEXT NOT NULL, estado TEXT NOT NULL, creado_utc TEXT NOT NULL)"
        )


def limpiar(valor):
    return CONTROL.sub("", valor or "").strip()


def guardar(datos):
    for _ in range(5):
        codigo = "ZP-" + "".join(secrets.choice(ALFABETO) for _ in range(8))
        try:
            with conectar() as con:
                con.execute(
                    "INSERT INTO gestiones VALUES (?, ?, ?, ?, ?, ?, 'Recibida', ?)",
                    (codigo, datos["tipo"], datos["vehiculo"], datos["nombre"], datos["correo"],
                     datos["mensaje"], datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")),
                )
            return codigo
        except sqlite3.IntegrityError:
            continue
    raise RuntimeError("No se pudo generar un código único")


@app.after_request
def cabeceras(resp):
    if request.method == "POST":
        resp.headers["Cache-Control"] = "no-store"
    return resp


@app.get("/")
def inicio():
    return render_template("inicio.html", vehiculos=VEHICULOS)


@app.get("/salud")
def salud():
    return "ok", 200, {"Content-Type": "text/plain; charset=utf-8"}


@app.get("/gestiones")
def formulario():
    return render_template("gestiones.html", tipos=TIPOS, vehiculos=VEHICULOS, datos={}, errores=[])


@app.post("/gestiones")
def crear():
    datos = {k: limpiar(request.form.get(k)) for k in ("tipo", "vehiculo", "nombre", "correo", "mensaje")}
    errores = []
    if datos["tipo"] not in TIPOS:
        errores.append("Elige el tipo de gestión.")
    if datos["vehiculo"] not in VEHICULOS:
        errores.append("Elige un vehículo de la lista.")
    if not 2 <= len(datos["nombre"]) <= 60:
        errores.append("El nombre debe tener entre 2 y 60 caracteres.")
    if len(datos["correo"]) > 120 or not RE_CORREO.match(datos["correo"]):
        errores.append("Escribe un correo válido (ficticio).")
    if len(datos["mensaje"]) > 300:
        errores.append("El mensaje no puede superar 300 caracteres.")
    if errores:
        return render_template("gestiones.html", tipos=TIPOS, vehiculos=VEHICULOS, datos=datos, errores=errores), 400
    codigo = guardar(datos)
    return render_template("resultado.html", codigo=codigo, tipo=TIPOS[datos["tipo"]],
                           vehiculo=VEHICULOS[datos["vehiculo"]])


@app.route("/consulta", methods=["GET", "POST"])
def consulta():
    if request.method == "GET":
        return render_template("consulta.html", tipos=TIPOS, vehiculos=VEHICULOS)
    codigo = limpiar(request.form.get("codigo")).upper()
    if not RE_CODIGO.match(codigo):
        return render_template("consulta.html", tipos=TIPOS, vehiculos=VEHICULOS, codigo=codigo[:20],
                               error="El código debe tener el formato ZP- seguido de 8 caracteres."), 400
    with conectar() as con:
        fila = con.execute("SELECT tipo, vehiculo, estado, creado_utc FROM gestiones WHERE codigo = ?",
                           (codigo,)).fetchone()
    if fila is None:
        return render_template("consulta.html", tipos=TIPOS, vehiculos=VEHICULOS, codigo=codigo,
                               error="No encontramos una gestión con ese código."), 404
    return render_template("consulta.html", tipos=TIPOS, vehiculos=VEHICULOS, codigo=codigo, fila=fila)


@app.errorhandler(404)
def no_encontrada(_):
    return render_template("error.html", titulo="Página no encontrada", detalle="La dirección no existe."), 404


@app.errorhandler(413)
def muy_grande(_):
    return render_template("error.html", titulo="Solicitud demasiado grande", detalle="Reduce el tamaño del mensaje."), 413


try:
    iniciar_db()
except (OSError, sqlite3.Error):
    pass  # en pruebas locales sin directorio de datos; en la instancia lo crea el instalador
