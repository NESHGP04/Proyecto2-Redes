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
- [ ] Coordinar con quien tenga el MD_2 (subredes y rutas): la VPC ya existe y está lista para crear las siete subredes.
