# Guía de dominio y DNS

## Dominio elegido: `dernait.com` (de Kevin), con DNS en Cloudflare

| Nombre | Tipo | Apunta a | Para qué | Proxy de Cloudflare |
|---|---|---|---|---|
| `zenite.dernait.com` | A | **18.210.66.163** (`eip-zenite-web`) | Web pública, HTTPS (P2) | **DNS only (nube gris)** |
| `zenite-vpn.dernait.com` | A | **3.228.84.176** (`eip-zenite-vpn`) | Servidor OpenVPN (P3) | **DNS only (nube gris)** |

- Los registros los creó Kevin en el DNS de Cloudflare de `dernait.com`. No se comparte ninguna credencial de su cuenta.
- **El proxy tiene que estar apagado (nube gris).** Con la nube naranja, Cloudflare responde con sus propias IP y Let's Encrypt validaría contra Cloudflare, no contra `zp-web-01`. Además, el proxy no pasa UDP/1194 de la VPN.
- `dernait.com` tiene un comodín (`*`) con proxy hacia el sitio de Kevin. Los registros explícitos `zenite` y `zenite-vpn` tienen prioridad sobre el comodín.
- No hay registros CAA, así que no se bloquea a Let's Encrypt.
- Compromiso con Kevin: dejar los registros al menos hasta después de la entrega del **12 nov 2026**.
- Si alguien libera o recrea una Elastic IP, la IP cambia y Kevin debe actualizar el registro. Por eso no se liberan sin avisar a P1.

### Verificación (DNS-01 y DNS-02)
Resultado del 6 nov 2026: `zenite.dernait.com` → 18.210.66.163 con `@8.8.8.8` y `@1.1.1.1` (OK). `zenite-vpn.dernait.com` → 3.228.84.176.
Evidencia: `FaseFinal/evidencias/01_infra_dmz_dominio/FINAL_DNS-01_02_resolucion_dernait.txt`.

```bash
bash FaseFinal/configuracion/P1_dns_check.sh zenite.dernait.com 18.210.66.163
```

## Alternativas descartadas (por si el dominio de Kevin deja de estar disponible)

### Plan A: dominio gratis del GitHub Student Pack (Namecheap `.me`)
Student Pack aprobado el 5 nov 2026; los beneficios se activan a las 72 h (hacia el 8 nov). La oferta cambia: confirmar en `education.github.com/pack` que Namecheap siga ofreciendo un `.me` gratis por un año.
1. Canjear la oferta de Namecheap con la cuenta de GitHub verificada y registrar un `.me`; desmarcar todo extra de pago.
2. En Advanced DNS borrar los registros de parking y agregar `A @` y `A www` → `18.210.66.163` (TTL 5 min). Nameservers: Namecheap BasicDNS.
3. `bash P1_dns_check.sh <dominio> 18.210.66.163`.

### Plan B: DuckDNS
1. Entrar a `duckdns.org` con GitHub o Google y crear un subdominio (ej. `zenite-prestige`).
2. En **current ip** escribir `18.210.66.163` y pulsar **update ip** (la Elastic IP no cambia).
3. El token de DuckDNS es un secreto: va en el `.env`, nunca en el repo ni en el chat.

Cambiar de dominio solo exige repetir `certbot` con el nombre nuevo y actualizar el `server_name` de Nginx. La IP no cambia.

## Si el dominio no resuelve durante la demo
1. `bash P1_dns_check.sh zenite.dernait.com 18.210.66.163`: ver si falla la respuesta o la IP.
2. Confirmar que `eip-zenite-web` sigue asociada a `zp-web-01` (`bash P1_dmz_infra.sh --validar`).
3. Si la IP cambió, pedir a Kevin que corrija el registro `A` con la IP nueva.
4. Si Kevin activó el proxy (nube naranja) por error, el dominio resolverá a IP de Cloudflare (104.21.x o 172.67.x): pedir que lo ponga en gris.
5. Plan de emergencia: abrir el sitio por la Elastic IP (el navegador avisará del certificado) y explicar el fallo.
