# Filas de la matriz global · Persona 2

Para la Persona 5. Horas UTC. Los resultados salen de las capturas de `FaseFinal/evidencias/02_web_publica/`; las filas con «por subir» no tienen todavía su captura en el repositorio.

| ID | Resp. | Servicio | Origen → destino | Esperado | Obtenido | Hora | Estado | Fig. |
|---|---|---|---|---|---|---|---|---|
| PUB-01 | P2 | Portal | Celular (LTE) → `https://zenite.dernait.com` | Carga; la gestión de prueba se registra | Consulta del código `ZP-22DW79PR`: cotización, Mercedes-Benz Clase C 200, «Recibida», registrada 2026-11-09 00:19 UTC | 00:19 | PASS | PUB-01 |
| PUB-02 | P2 | Redirección | Mac → `http://zenite.dernait.com` | 301 a `https://` | `301 Moved Permanently`, `Location: https://zenite.dernait.com/`; `https://` `200 OK` | 00:15:40 | PASS | PUB-02 |
| PUB-03 | P2 | Certificado | Navegador → `zenite.dernait.com` | Válido, de Let's Encrypt | Emisor Let's Encrypt (YE2), válido del 8 nov 2026 al 6 feb 2027 | 23:13 (8 nov) | PASS | PUB-03 |
| PUB-04 | P2 | TLS | Mac → `:443` | TLS 1.2 o 1.3 y cadena | TLSv1.3, `AEAD-AES256-GCM-SHA384`, `Verify return code: 0 (ok)`; cadena no visible en la captura | 00:25:57 | PASS (cadena no visible) | PUB-04 |
| PUB-05 | P2 | TLS | Mac → `:443` con `-tls1` y `-tls1_1` | Rechazados | Ambos con `tlsv1 alert protocol version` (70), sin certificado | 00:27:19 / 00:27:25 | PASS | PUB-05 |
| PUB-06 | P2 | Aislamiento DMZ | `zp-web-01` → Intranet 80, LDAP 389/636, NTP UDP 123, TI 22 | Sin conexión | Tiempo agotado en todos; controles: los servicios escuchan en sus instancias | 00:36 a 00:53 | PASS | PUB-06 |
| PUB-07 | P2 | Superficie pública | Mac → `18.210.66.163:22` | Sin respuesta | `Operation timed out` | 00:54:55 | PASS | PUB-07 |
| PUB-08 | P2 | Renovación | `zp-web-01` | Simulación correcta; temporizador activo | `all simulated renewals succeeded`; `certbot.timer` activo | ≈ 00:23 | PASS | PUB-08 |
| WEB-01 | P2 | Intranet | `zp-ventas-01` → `http://10.20.0.71/` | HTTP 200 | `200 OK`, 8456 bytes | 02:03:48 | PASS | WEB-01 (por subir) |
| WEB-02 | P2 | Intranet | `zp-ti-01` → `http://10.20.0.71/` | HTTP 200 | `200 OK`, 8456 bytes | 01:23:13 | PASS | WEB-02 |
| WEB-03 | P2 | Intranet | `zp-ntp-01` (Servidores) → `http://10.20.0.71/` | HTTP 200 | `200 OK`, 8456 bytes | 01:25:57 | PASS | WEB-03 (por subir) |
| WEB-04 | P2 | Intranet | `zp-visitantes-01` → `http://10.20.0.71/` | Bloqueado | Tiempo agotado (5002 ms), código de salida 28 | 02:04:22 | PASS | WEB-04 (por subir) |
| WEB-05 | P2 | Intranet | Internet → Intranet | Inaccesible | SG de Servidores sin rangos de IP; `curl` desde la Mac agota el tiempo (8 s); falta captura de la instancia sin IPv4 pública | por completar | PASS parcial | WEB-05 (por subir) |

**Fallos y correcciones:** ninguna prueba falló. Se anotan como desviaciones la estructura de carpetas del instalador (corregida) y la apertura de TCP 80 y 443 en `zenite-dmz` por la Persona 2 sin autorización previa de la Persona 3 (ver el reporte, sección 5.2).