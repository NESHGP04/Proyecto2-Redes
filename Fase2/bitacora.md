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

**Pendiente (requiere acceso a AWS)**
- [ ] Ejecutar `00_verificar_entorno.sh` y `01_crear_vpc.sh` en CloudShell.
- [ ] Captura `E01_VPC_CIDR.png` y descargar `vpc.json` / `vpc-validacion.txt`.
- [ ] Anotar aquí el VPC ID real y el resultado de la validación.
