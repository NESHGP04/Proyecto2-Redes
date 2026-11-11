# Checkpoint 5 · Revisión de SNMP

**Estado: aprobado por el humano mediante «continua».** Se abre checkpoint 6 para Grafana; su implementación AWS sigue pendiente. Última prueba recibida: 11-nov-2026 08:39:37 UTC / 02:39:37 Guatemala. No equivale a cierre de toda P4 ni al apagado de la sesión.

**Cierre de cómputo recibido posteriormente:** diez instancias stopped, cero encendidas, según salida P1 sin hora propia visible. [Evidencia de apagado](../evidencias/04_snmp_ldap/FINAL_SNMP_cierre_instancias.txt). La sesión ya está cerrada en cómputo; las referencias a ocho running abajo describen el estado al terminar las pruebas, antes del apagado. El apagado se recibió antes de la aprobación explícita posterior «continua»; esa aprobación permite iniciar el checkpoint 6.

## 1. Qué se hizo

Se instalaron y validaron agentes SNMPv3 authPriv SHA-256/AES, de solo lectura, en los diez hosts, en sus intervalos.
El monitor recibió uptime, CPU, RAM, raíz, interfaces y procesos de todos por tandas, con Prometheus/exporter privados y diez objetivos conservados.
Se comprobó rechazo de clave errónea y falta de respuesta desde Ventas, Visitantes y CloudShell exterior, con controles positivos.
Ventas-02 pasó de up a down tras parada EC2 y volvió a responder/up después del inicio.
TI fue restaurada, NAT/EIP temporal eliminados y el temporal del rescate está ausente; se preservaron las excepciones públicas Web/VPN.

## 2. Archivos

Todo bajo FaseFinal; no se modificaron scripts de Fases 2/3 ni la matriz global.

- Configuración: `P4_snmp.py`, `P4_snmp.sh`, `P4_monitor_snmp.sh`, `P4_snmp_nube.sh`, `P4_snmp_internet.sh`, `P4_snmp_objetivos.csv`, `P4_snmp.env.example`.
- Operación/diseño: [P4_snmp_operacion.md](P4_snmp_operacion.md), [P4_snmp_diseno.md](P4_snmp_diseno.md), `P4_solicitud_red_monitoreo.md`, este cierre.
- Rescate acotado: `P4_recuperar_archivos_cloudshell.sh`.
- Pruebas locales: `tests/P4_snmp_seguridad.py`, `tests/P4_snmp_nube_casos.py`, `tests/P4_recuperar_archivos_casos.py`, `tests/P4_snmp_internet_casos.py`.
- Bitácora: [P4.md](../bitacora/P4.md).
- Evidencias: `evidencias/04_snmp_ldap/FINAL_SNMP*` y `FINAL_FW-05*`; [filas preparadas para P5](../evidencias/04_snmp_ldap/FINAL_SNMP_filas_para_P5.md).

### Índice de agentes y cobertura

| Hosts | Evidencia de agente |
|---|---|
| Monitor | [SNMP-01 monitor](../evidencias/04_snmp_ldap/FINAL_SNMP-01_monitor_agente.txt) |
| LDAP | [SNMP-01 LDAP](../evidencias/04_snmp_ldap/FINAL_SNMP-01_ldap_y_control_monitor.txt) |
| Ventas-01 | [SNMP-01 Ventas](../evidencias/04_snmp_ldap/FINAL_SNMP-01_ventas_agente.txt) |
| TI / Ventas-02 | [SNMP-01 TI y Ventas-02](../evidencias/04_snmp_ldap/FINAL_SNMP-01_ti_ventas02_y_ntp_interrumpido.txt) |
| NTP | [SNMP-01 NTP](../evidencias/04_snmp_ldap/FINAL_SNMP-01_ntp_agente.txt) |
| Intranet | [SNMP-01 Intranet](../evidencias/04_snmp_ldap/FINAL_SNMP-01_intranet_agente.txt) |
| Visitantes | [SNMP-01 Visitantes](../evidencias/04_snmp_ldap/FINAL_SNMP-01_visitantes_agente.txt) |
| Web | [SNMP-01 Web](../evidencias/04_snmp_ldap/FINAL_SNMP-01_web_agente.txt) |
| VPN | [SNMP-01 VPN](../evidencias/04_snmp_ldap/FINAL_SNMP-01_vpn_agente.txt) |

Métricas: [cobertura de diez hosts × seis familias](../evidencias/04_snmp_ldap/FINAL_SNMP-02_cobertura_por_host.md). Las filas de P5 enlazan autenticación, caída/recuperación y aislamiento completos.

## 3. Cómo revisar

1. Revisar las cinco filas propuestas y seguir sus archivos de evidencia. SNMP-02 declara tandas, no diez concurrentes; SNMP-04 conserva up → parada/stopped → down → inicio/running → up.
2. Última salida de 08:39:16 UTC / 02:39:16 Guatemala: control autenticado a Ventas-02 exit 0 y scrape up; ocho up, Visitantes/VPN down, coherentes con sus paradas. Prometheus/exporter siguen activos/privados con diez targets.
3. A las 08:39:37 UTC / 02:39:37 Guatemala se comprobó ausencia del archivo y de enlace simbólico `.env.p4-snmp-rescate`; no se mostró contenido. [Evidencia](../evidencias/04_snmp_ldap/FINAL_SNMP-04_ventas02_recuperacion.txt).
4. Configuración: agentes en IP privada UDP 161; sin comunidades v1/v2c; rouser priv y vista de métricas. Restricción de origen mediante SG/ACL TI, no un SOURCE inexistente en rouser. Exporter/Prometheus loopback 9116/9090, sin puertos nuevos abiertos.
5. Pruebas locales ya registradas: 28 casos de seguridad (nueve de recuperación en contenedor root aislado sin red), 14 casos AWS de solo lectura, ocho de rescate, nueve del guion exterior. Integraciones Net-SNMP Ubuntu/AL2023 y Prometheus/exporter reales registradas como locales; no se confunden con pruebas EC2. No hace falta reinstalar ni repetir el despliegue para revisar.

Comandos de lectura en Fedora, desde el repositorio:

```bash
git status --short
git diff --check
```

Las imágenes locales ya existentes no se consideran revisadas por este cierre. Un archivo untracked no aparece en git diff ordinario; abrir también los archivos nuevos indicados arriba.

## 4. Capturas a aportar/verificar

Las transcripciones reales están guardadas; no se han fabricado capturas de terminal. Se pueden capturar los registros ya conservados mostrando su fecha original y señalando que son evidencia guardada, sin repetir apagados ni exponer claves.

| Nombre propuesto | Debe verse |
|---|---|
| FINAL_SNMP-01_agente.png | Host, hora, escucha privada y validación autenticada del agente; conservar además TXT de los diez |
| FINAL_SNMP-02_metricas.png | Host consultado, hora y datos reales de las seis familias; índice con cobertura por tandas |
| FINAL_SNMP-03_autenticacion.png | Rechazo de clave y resultado de controles correctos, sin contraseña |
| FINAL_SNMP-04_recuperacion.png | Registros originales up/down/up con sus fechas y estado EC2 relacionado |
| FINAL_SNMP-05_origenes.png | Timeout de Ventas/Visitantes/exterior y controles; pueden necesitarse varias imágenes |

No incluir .env, perfiles de cliente, transporte privado, USM, llaves ni origen público de CloudShell. Las EIP autorizadas de Web/VPN sí pueden figurar.

## 5. Problemas y límites

- Límite informado 16 vCPU: diez t3 requieren 20; se trabajó por tandas, máximo ocho running. La consulta ServiceQuotas fue denegada. La causa del rechazo adicional al iniciar Web/VPN juntas no quedó confirmada; sus inicios individuales funcionaron. No se cambió cuota/IAM/tipo.
- El primer despliegue del monitor rechazó el directorio raíz legítimo del tar. Se corrigió, probaron ambos archivos oficiales y recuperó el estado parcial; fallo y corrección están documentados.
- Un pegado de transcripción truncó archivos de transporte a cero bytes. Hubo rescate y luego instalaciones reales correctas. No se recibió su salida pública completa: la ausencia temporal está ahora acreditada, pero no se reconstruyen todos sus pasos/backups.
- Validadores heredados P1/P5 devuelven fallas al esperar DMZ/VPN sin las excepciones de Final. Se mantienen esos resultados fallidos distinguiendo de TI correctamente restaurada y NAT temporal eliminado; no se borraron EIP/rutas de Web/VPN para satisfacerlos.
- CPU/red recibidos son contadores; una muestra no prueba tasas estables. Timeout UDP no identifica por sí solo el filtro. Las horas de arranque/parada EC2 no son exactas, así que no se calculan latencias.
- Ocho instancias siguen running según la última tabla recibida; Visitantes/VPN stopped. NAT quedó eliminado y dos EIP legítimas siguen asociadas según el último diagnóstico. Las instancias no se dan por apagadas sin recibir el resultado del cierre.

Si se pausa la sesión para revisión, el humano puede cerrar el cómputo usado por P4 con P1, deteniendo explícitamente las ocho instancias restantes. Interrumpe sus servicios hasta el siguiente inicio; conserva discos, datos y configuración. Desde CloudShell:

```bash
bash "$HOME/P1_instancias.sh" detener zp-monitor-01 zp-ldap-01 zp-ti-01 zp-ventas-01 zp-ventas-02 zp-ntp-01 zp-intranet-01 zp-web-01
```

**Ejecutado por el humano y acreditado:** tabla final de las diez stopped y cero encendidas, sin hora propia visible. El asistente no ejecutó la operación. NAT ya eliminado; no repetir su creación/destrucción. Las EIP y EBS previstos siguen existiendo aunque EC2 esté detenido.

## 6. Decisión de revisión

Se solicita aprobar checkpoint 5 con cobertura por tandas y límites documentados para pasar a Grafana. La opción B y SNMPv3 ya fueron aprobadas: no se pide elegir de nuevo plataforma/algoritmo. Si el equipo exige diez hosts simultáneos en la demo, esa capacidad requiere coordinación adicional; no se infiere aprobación para ampliar cuota o cambiar instancias.

La pausa proviene de R2 y secciones 7/8 del documento de instrucciones P4 entregado por el humano: el checkpoint 6 solo comienza con el 5 cerrado. Grafana y reporte final siguen pendientes.

## 7. Entregas y coordinación

- P3: [FW-05 listo para entrega humana](../evidencias/04_snmp_ldap/FINAL_FW-05_entrega_P3.md); cierra su fila.
- P5: [cinco filas SNMP](../evidencias/04_snmp_ldap/FINAL_SNMP_filas_para_P5.md) con vínculos y límites, para incorporar/revisar en su matriz.
- P1: ventana de red cerrada, confirmar apagado al cerrar sesión y coordinar próximo encendido. No se solicita NAT nuevo para esta revisión.
- Próximo checkpoint: Grafana privado por túnel EICE desde Fedora, con herramientas/identidad IAM local todavía por comprobar. Sin puertos 3000/9090/9116 abiertos en AWS.

No se enviaron mensajes a terceros ni se modificaron archivos de sus paquetes.

## 8. Propuesta de commit humano

Revisar antes todos los archivos nuevos y la evidencia. Los comandos siguientes son una propuesta para el humano desde Fedora; el asistente no los ejecutó. Solo incluyen el paquete SNMP y bitácora, sin imágenes ajenas ni cambios LDAP previos.

```bash
git add -- FaseFinal/configuracion/P4_snmp* \
  FaseFinal/configuracion/P4_monitor_snmp.sh \
  FaseFinal/configuracion/P4_recuperar_archivos_cloudshell.sh \
  FaseFinal/configuracion/P4_solicitud_red_monitoreo.md \
  FaseFinal/configuracion/tests/P4_snmp* \
  FaseFinal/configuracion/tests/P4_recuperar_archivos_casos.py \
  FaseFinal/evidencias/04_snmp_ldap/FINAL_SNMP* \
  FaseFinal/evidencias/04_snmp_ldap/FINAL_FW-05* \
  FaseFinal/bitacora/P4.md
git diff --cached --stat
git diff --cached
git commit -m "feat(snmp): validar monitoreo v3 y aislamiento por tandas"
```

**Aprobación recibida: «continua». Checkpoint 5 cerrado; checkpoint 6 iniciado.**
