# Filas de la matriz de pruebas · Persona 1

Formato de la matriz de Fase 3. Las columnas **Obtenido**, **Hora**, **Estado** y **Fig.** solo se llenan con una prueba que tenga evidencia. Horas en UTC (Guatemala es UTC−6: 00:08 UTC del 6 nov = 18:08 del 5 nov).
Evidencias en `FaseFinal/evidencias/01_infra_dmz_dominio/`.

| ID | Resp. | Servicio | Origen → destino | Esperado | Obtenido | Hora | Estado | Fig. |
|---|---|---|---|---|---|---|---|---|
| DMZ-01 | P1 | Salida a Internet | `zp-web-01` y `zp-vpn-01` → `curl -s https://checkip.amazonaws.com` (por EICE) | Cada una devuelve su Elastic IP | `zp-web-01` → `18.210.66.163`; `zp-vpn-01` → `3.228.84.176` | 2026-11-06 00:09 – 00:29 | OK | `FINAL_DMZ-01_checkip_web.png`, `curl_vpn.png` |
| DMZ-02 | P1 | Rutas | `rt-zenite-dmz` y `rt-zenite-vpn`; `subnet-zenite-vpn` | `0.0.0.0/0 → igw-zenite-fase3` activa en ambas; la subred VPN asociada a `rt-zenite-vpn` | Ambas `igw-00f6efb87a444f270 active`; `subnet-zenite-vpn` en `rtb-0c4e169f00a248de8` | 2026-11-06 00:08 | OK | `FINAL_DMZ-01_04_validacion_base_publica.txt` |
| DMZ-03 | P1 | IP pública | Barrido de las instancias `zp-*` | Solo `zp-web-01` y `zp-vpn-01` con IP pública | Ninguna otra con IP pública; `zp-monitor-01` sin IPv4 pública | 2026-11-06 00:08 | OK | `FINAL_DMZ-01_04_validacion_base_publica.txt` |
| DMZ-04 | P1 | Acceso SSH | CloudShell → TCP/22 de `18.210.66.163` y `3.228.84.176`; SSH por EICE | Puerto 22 cerrado desde Internet; SSH solo por EICE | Puerto 22 cerrado en ambas IP; sesión SSH por EICE abierta como `ubuntu` en `zp-web-01` y `zp-vpn-01` | 2026-11-06 00:08 | OK | `FINAL_DMZ-01_04_validacion_base_publica.txt`, capturas de DMZ-01 |
| DNS-01 | P1 | DNS | `dig +short zenite.dernait.com` | Devuelve la Elastic IP de la web | `18.210.66.163` (también `zenite-vpn.dernait.com` → `3.228.84.176`) | 2026-11-06 00:03 | OK | `FINAL_DNS-01_02_resolucion_dernait.txt` |
| DNS-02 | P1 | DNS | `@8.8.8.8` y `@1.1.1.1` → `zenite.dernait.com` | Misma respuesta en dos resolutores | Ambos devuelven `18.210.66.163` | 2026-11-06 00:03 | OK | `FINAL_DNS-01_02_resolucion_dernait.txt` |
| COST-01 | P1 | Presupuesto | Billing > Budgets y `P1_costos.sh --todo` | Presupuesto, alerta y estimación documentados | «My Monthly Cost Budget» de US$15/mes con alertas al 85 % y 100 % reales y 100 % de pronóstico; gasto del mes US$2.17; pronóstico del mes US$8.39; estimación con todo encendido ≈ US$1.24 al día | 2026-11-06 00:25 | OK | `FINAL_COST-01_costos.txt`, `Billing_and_cost.png` |

## Notas
- Falta confirmar a qué correo llegan las alertas del presupuesto (Billing > Budgets > Alerts). No cambia el resultado de COST-01, pero hay que dejarlo anotado en el reporte.
- Las filas se actualizan si se repite una prueba (con el número entre paréntesis, como en Fase 3).
