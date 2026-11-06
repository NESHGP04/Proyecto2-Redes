# Filas de la matriz de pruebas · Persona 1

Formato de la matriz de Fase 3. Las columnas **Obtenido**, **Hora**, **Estado** y **Fig.** solo se llenan con una prueba que tenga evidencia; las filas sin evidencia quedan vacías o como *pendiente*. Horas en UTC (Guatemala es UTC−6: 00:08 UTC del 6 nov = 18:08 del 5 nov).
Evidencias en `FaseFinal/evidencias/01_infra_dmz_dominio/`.

| ID | Resp. | Servicio | Origen → destino | Esperado | Obtenido | Hora | Estado | Fig. |
|---|---|---|---|---|---|---|---|---|
| DMZ-01 | P1 | Salida a Internet | `zp-web-01` → `curl -s https://checkip.amazonaws.com` (por EICE) | Devuelve la Elastic IP `18.210.66.163` | | | Pendiente | |
| DMZ-02 | P1 | Rutas | `rt-zenite-dmz` y `rt-zenite-vpn`; `subnet-zenite-vpn` | `0.0.0.0/0 → igw-zenite-fase3` activa en ambas; la subred VPN asociada a `rt-zenite-vpn` | Ambas `igw-00f6efb87a444f270 active`; `subnet-zenite-vpn` en `rtb-0c4e169f00a248de8` | 2026-11-06 00:08 | OK | `FINAL_DMZ-01_04_validacion_base_publica.txt` |
| DMZ-03 | P1 | IP pública | Barrido de las instancias `zp-*` | Solo `zp-web-01` y `zp-vpn-01` con IP pública | Ninguna otra con IP pública; `zp-monitor-01` sin IPv4 pública | 2026-11-06 00:08 | OK | `FINAL_DMZ-01_04_validacion_base_publica.txt` |
| DMZ-04 | P1 | Acceso SSH | CloudShell → TCP/22 de `18.210.66.163` y `3.228.84.176`; SSH por EICE | Puerto 22 cerrado desde Internet; SSH solo por EICE | Puerto 22 cerrado en ambas IP. Falta comprobar el acceso SSH por EICE | 2026-11-06 00:08 | Pendiente | `FINAL_DMZ-01_04_validacion_base_publica.txt` |
| DNS-01 | P1 | DNS | `dig +short zenite.dernait.com` | Devuelve la Elastic IP de la web | `18.210.66.163` (también `zenite-vpn.dernait.com` → `3.228.84.176`) | 2026-11-06 00:03 | OK | `FINAL_DNS-01_02_resolucion_dernait.txt` |
| DNS-02 | P1 | DNS | `@8.8.8.8` y `@1.1.1.1` → `zenite.dernait.com` | Misma respuesta en dos resolutores | Ambos devuelven `18.210.66.163` | 2026-11-06 00:03 | OK | `FINAL_DNS-01_02_resolucion_dernait.txt` |
| COST-01 | P1 | Presupuesto | Billing → Budgets | Presupuesto, alerta y estimación documentados | | | Pendiente | |

## Qué falta para cerrar las filas pendientes

- **DMZ-01 y DMZ-04 (SSH por EICE):** entrar por EICE a `zp-web-01` y `zp-vpn-01` y ejecutar `curl -s https://checkip.amazonaws.com`; debe devolver la Elastic IP de cada una. Captura de pantalla de la sesión (`FINAL_DMZ-01_checkip_web.png`).
- **COST-01:** captura de Billing > Budgets con el límite de US$20 y la alerta en US$15, tomada por la dueña de la cuenta; más la salida de `bash P1_costos.sh --todo` (`FINAL_COST-01_costos.txt`) y la tabla de costos del reporte.
