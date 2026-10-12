# Bitácora – Fase 2 (parte AWS y VPC · Marinés)

## 2026-10-09

**1. Análisis de las instrucciones**
- Leídos: PDF de Fase 2, `MD_1` a `MD_6` y el reporte final de Fase 1 (V3).
- Mi parte: `MD_1` (preparar AWS y crear la VPC `vpc-zenite-fase2`, estructura de evidencias, captura E01).
- Fase 2 es un **prototipo**: el MD_3 usa EC2 Instance Connect Endpoint y no hay NAT Gateway ni pfSense, a diferencia del
  diseño completo de Fase 1. Esa diferencia debe quedar explicada en el reporte como decisión del prototipo.

**2. Observaciones sobre los MD**
- El MD_1 sugiere nombres de captura de ejemplo (`E04_Security_Groups`, `E05_Instancias`, …) distintos a los de MD_2–MD_5
  (`E04_SG_Ventas`, `E07_Instancias_Privadas`, …). Se usan los de MD_2–MD_5.
- Direcciones comprobadas contra la regla de AWS (4 primeras + última reservadas): `.10`, `.11` (Ventas) y `.102` (TI) son asignables.

**3. Decisiones**
- Trabajo directo en `main` (sin ramas); los commits los hace Marinés tras revisar cada bloque. Estilo de commits como en Lab5
  (`feat(...)`, `docs(...)`).
- La VPC se crea con un script de AWS CLI para CloudShell (reproducible, mismas etiquetas siempre) y se verifica/captura en la consola.
- Del Lab5 se reutiliza la forma de trabajo (bitácora, scripts que guardan evidencia, `evidencias/`). Los archivos de BIND9 y OpenLDAP
  se adaptarán más adelante a `10.20.0.72` y `10.20.0.69`; no se reutilizan las IPs `192.168.71.x` del laboratorio.

**4. Archivos creados (sin commit, para revisión)**
- `.gitignore` (secretos y temporales).
- `Fase2/` con la estructura de evidencias, `README.md` y esta bitácora.
- `Fase2/configuracion/00_verificar_entorno.sh` y `01_crear_vpc.sh`.

**5. Ejecución en AWS (2026-10-09, 18:32 hora de Guatemala)**
- Scripts ejecutados en CloudShell (`us-east-1`). Los tres commits de la estructura y los scripts ya están en `origin/main`.
- VPC creada: `vpc-zenite-fase2` · `vpc-0e4c1d0b2314ab4df` · `10.20.0.0/24`. Validación completa en `[OK]`
  (estado, CIDR, sin IPv6, tenancy default, DNS resolution y hostnames, 5 etiquetas). Control de costos: EC2, NAT, Elastic IP y VPN en 0.
- La cuenta ya tenía la VPC predeterminada `172.31.0.0/16`; no se solapa con la del prototipo.
- Evidencias: `evidencias/01_vpc/E01_VPC_CIDR.png` (con región, VPC ID, CIDR, estado y DNS), `configuracion/vpc.json` y
  `configuracion/vpc-validacion.txt`.
- Sección del reporte redactada: `reporte/01_preparacion_aws_y_vpc.md`.

**Aviso:** `vpc.json` (campo `OwnerId`) y la captura E01 muestran el ID de la cuenta de AWS. No es una credencial, pero identifica la cuenta.

**Estado de la parte AWS y VPC (MD_1): completa.**
- [x] Coordinar con quien tenga el MD_2 (subredes y rutas): la VPC ya existe y está lista para crear las siete subredes.

# Bitácora – Fase 2 (parte subredes y rutas · MD_2)

## 2026-10-10

**1. Punto de partida**
- VPC entregada: `vpc-zenite-fase2` · `vpc-0e4c1d0b2314ab4df` · `10.20.0.0/24` · `us-east-1`, con DNS resolution/hostnames y etiquetas.
- Nombres de subredes, route tables y evidencias tomados del `README.md` de Fase 2 y del MD_2.

**2. Decisiones**
- Se automatiza con `configuracion/02_crear_subredes_rutas.sh` (mismo estilo que `01_crear_vpc.sh`: CloudShell, idempotente,
  modo `--validar`, salida en `~/fase2-config/`). Así los IDs de `segmentacion.md` salen directamente de AWS y no se copian a mano.
- AZ única `us-east-1a` (configurable con `AZ=`). Las subredes llevan también `Owner=Grupo30` para ser consistentes con la VPC.
- Se desactiva `MapPublicIpOnLaunch` en las siete subredes (ya es el valor por defecto en una VPC no predeterminada; se fuerza
  para que quede explícito).
- La tabla principal de la VPC no se modifica ni se usa: todas las subredes tienen asociación explícita.
- El script se detiene sin cambiar nada ante: subred con CIDR fuera del plan (incluye las reservas), subred del plan en otra AZ,
  route tables duplicadas o AZ inexistente. La validación falla si alguna tabla tiene una ruta distinta de la local o si hay
  un Internet Gateway asociado a la VPC.
- Se agregó `.env.example` (nombres de variables sin valores) y `!.env.example` en `.gitignore`; `.env`, `.env.*`, `*.pem` y
  `*.key` siguen ignorados. Los tres scripts cargan `.env` si existe, para poder usarlos fuera de CloudShell.

**3. Pruebas del script (sin AWS)**
- Probado contra un simulador local de la API de EC2: creación completa, reejecución sin cambios, `--validar`, subred sobre
  `10.20.0.160/27`, subred en `us-east-1b`, subred asociada a la tabla equivocada (se corrige), ruta `0.0.0.0/0` a un IGW en la
  DMZ (la validación falla) y AZ inexistente. Todos con el resultado esperado.

## 2026-10-12

**4. Ejecución en AWS (01:28 hora de Guatemala)**
- Acceso a la cuenta del grupo (`7034-6191-7799`) con un usuario IAM propio creado por Marinés (las subredes deben vivir en la
  misma cuenta y VPC que la E01). El usuario no tiene permisos de Billing; la revisión de costos la hace Marinés.
- `bash 01_crear_vpc.sh --validar`: todo `[OK]`, la VPC sigue igual.
- `bash 02_crear_subredes_rutas.sh`: 7 subredes y 3 route tables creadas y asociadas; validación completa en `[OK]`
  (sin solapamientos, reservas libres, solo ruta local, sin IGW, EC2/NAT/EIP en 0).
- IDs reales registrados en `configuracion/segmentacion.md` y salida en `configuracion/subredes-validacion.txt`.
- `subnets.json` y `route-tables.json` copiados desde CloudShell con `cat` (la descarga no funciona desde el panel inferior de
  la consola en este navegador). Verificados con `jq`: mismos IDs que `segmentacion.md`; la tabla principal
  `rtb-0018789e96aaf0a54` no tiene subredes asociadas.

**5. Capturas**
- `E02_Subredes_AWS.png`: Subnets filtrado por la VPC (7), con Subnet ID, CIDR, IP disponibles y AZ `us-east-1a`.
- La E03 se dividió en tres capturas (una por tabla, con la pestaña *Routes* y la columna de asociaciones), porque en una sola
  no se veían las rutas de las tres: `E03_Rutas_Interna.png`, `E03_Rutas_DMZ.png`, `E03_Rutas_Infra.png`.
- Extra no incluida: el *Resource map* de la VPC (subredes ↔ route tables) puede servir para la presentación.

**Estado de la parte subredes y rutas (MD_2): completa.**

**6. Pendiente**
- [ ] Revisar Billing al terminar (Marinés). No se crearon NAT Gateway, Elastic IP ni instancias en este paso.
