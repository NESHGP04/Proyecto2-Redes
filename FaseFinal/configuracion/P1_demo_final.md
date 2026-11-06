# Fase final – Plan de encendido para la demo y guion de la parte de infraestructura (P1)

Demo: **martes 10 de noviembre de 2026**. Fuera de la demo todo debe estar apagado (la cuenta no tiene créditos), pero la demo necesita las instancias nuevas y las de Fase 3 encendidas.
Este plan dice **cuánto antes encender**, qué comprobar, cómo mostrar la parte de infraestructura (≈ 2 min), cómo apagar y qué hacer si algo falla.

> **Regla de oro:** `P1_instancias.sh encender` y `detener` **sin nombres actúan sobre todas las `zp-*`** (las 10). Se usan siempre con nombres explícitos.
> Los scripts se corren en CloudShell. Las pruebas de red desde fuera (DNS, puertos) se pueden correr desde la computadora.

## Tiempos observados (5 de noviembre de 2026)

| Paso | Duración observada |
|---|---|
| `bash P1_dmz_infra.sh crear` (rutas, Security Groups, tres instancias, dos Elastic IP, hasta `todo correcto`) | ≈ 5 a 6 min (21:50 → 21:56 UTC, incluye una validación previa) |
| Encender las tres instancias nuevas hasta status checks `ok/ok` | ≈ 3 a 4 min (`initializing` a los 2 min; `ok/ok` a los 3 a 4 min) |
| Encender instancias de Fase 3 ya creadas | de 3 a 5 min (medido el 21 de octubre) |
| Conectarse por EICE | segundos |
| `P1_costos.sh --todo` | ≈ 1 min (el barrido de regiones es lo más lento) |

**Encender todo lleva unos 10 minutos.** Conviene empezar **45 minutos antes** de la presentación para tener margen. Encendida, la infraestructura nueva cuesta ≈ US$0.05 por hora.

**Recomendación para quitar el riesgo de capacidad:** el 5 de noviembre AWS devolvió `InsufficientInstanceCapacity` al encender (ver «Si algo falla»). Para no depender de eso el martes, encender web, VPN y monitor
**el lunes 9 por la tarde**, para el ensayo, y dejarlas encendidas hasta la demo (≈ US$1.50 por día con todo encendido). Si no, encender el martes a primera hora.

## Lista de verificación previa (T − 45 min)

1. **Billing y costos:** `bash P1_costos.sh --todo`. Debe mostrar el gasto del mes dentro del tope (alerta en US$15, tope del equipo US$20), 0 NAT, 0 Elastic IP sin asociar y «Otras regiones» sin recursos.
2. **Encender solo lo que usará la demo, por nombre.** Primero lo crítico y de una en una (así se ve cuál falla):
   ```bash
   for n in zp-web-01 zp-vpn-01 zp-monitor-01; do bash P1_instancias.sh encender $n || echo "FALLO $n"; done
   ```
   Luego las de Fase 3 que pida el guion de P5, por ejemplo:
   ```bash
   bash P1_instancias.sh encender zp-ldap-01 zp-intranet-01 zp-ntp-01 zp-ventas-01 zp-ti-01 zp-visitantes-01
   ```
3. **Validar** (esperar 3 a 4 min si aparece `initializing`): `bash P1_dmz_infra.sh --validar` → `RESULTADO: todo correcto.`
4. **DNS (desde la computadora):** `bash FaseFinal/configuracion/P1_dns_check.sh zenite.dernait.com 18.210.66.163` → DNS-01 y DNS-02 en `[OK]`.
5. **Salida de las dos instancias públicas (por EICE):** en `zp-web-01` y `zp-vpn-01`, `curl -s https://checkip.amazonaws.com` devuelve `18.210.66.163` y `3.228.84.176`.
6. **Desde fuera:** `nc -vz -w 5 18.210.66.163 22` **no** conecta (puerto 22 cerrado); `https://zenite.dernait.com` abre en el navegador (lo prepara P2) y la VPN conecta (lo prepara P3).
7. **Ensayo:** correr una vez el guion de abajo. Anotar a mano los Instance IDs y las IP públicas.
8. **Congelar:** no cambiar reglas, scripts ni DNS en los 5 minutos anteriores.
9. **Respaldo:** tener abiertas las capturas de `FaseFinal/evidencias/01_infra_dmz_dominio/` y los JSON de `FaseFinal/configuracion/` por si la consola de AWS va lenta.

El NAT **no** se necesita el día de la demo (todo debe estar instalado antes del congelamiento del lunes 9 a las 18:00). Si P5 pide NAT para algo, ver `P1_calendario_nat.md`.
Recordatorio: `P1_gateways.sh --validar` de Fase 3 marca `[FALLA]` esperadas (ruta por defecto en `rt-zenite-dmz` y Elastic IP ≠ 0); no se usa en esta fase.

## Guion de la parte de infraestructura (≈ 2 min)

1. **Consola → VPC → Route tables:**
   - `rt-zenite-dmz` y `rt-zenite-vpn`: `0.0.0.0/0 → igw-zenite-fase3`. En `rt-zenite-vpn`, pestaña *Subnet associations*: `subnet-zenite-vpn`.
   - Decir que son **las únicas subredes con ruta directa a Internet**; el resto sale solo por el NAT, cuando existe.
2. **EC2 → Elastic IPs:** `eip-zenite-web` → `zp-web-01` (`18.210.66.163`) y `eip-zenite-vpn` → `zp-vpn-01` (`3.228.84.176`).
3. **EC2 → Instances:** solo `zp-web-01` y `zp-vpn-01` tienen IPv4 pública; las demás `zp-*`, ninguna. (Columna *Public IPv4 address*.)
4. **EC2 → Security Groups:**
   - `zenite-dmz`: TCP/80 y TCP/443 desde `0.0.0.0/0` (la web) y SSH solo desde `zenite-eice`.
   - `zenite-vpn`: UDP/1194 desde `0.0.0.0/0` y SSH solo desde `zenite-eice`.
   - Decir que **son las únicas tres entradas abiertas a Internet** de toda la red (decisión D10).
5. **DNS:** en una terminal, `dig +short zenite.dernait.com` → `18.210.66.163`, la Elastic IP de la web; abrir `https://zenite.dernait.com`.
6. **Acceso administrativo:** `nc -vz -w 5 18.210.66.163 22` se queda sin respuesta. Las instancias se administran solo por EC2 Instance Connect Endpoint (no hay puerto SSH público).
7. **Costos:** mostrar Billing (gasto del mes y presupuesto de US$15 en estado OK) o `bash P1_costos.sh`; decir que todo se apaga al terminar y que una Elastic IP apagada solo cuesta ≈ US$0.12 por día.

## Después de la demo

1. Apagar solo lo que se encendió, por nombre:
   ```bash
   bash P1_instancias.sh detener zp-web-01 zp-vpn-01 zp-monitor-01 zp-ldap-01 zp-intranet-01 zp-ntp-01 zp-ventas-01 zp-ti-01 zp-visitantes-01
   ```
2. `bash P1_dmz_infra.sh --validar-apagado` → 0 NAT, ninguna `zp-*` encendida y solo nuestras dos Elastic IP.
3. `bash P1_costos.sh` → sin hallazgos (queda ≈ US$0.47 por día en Elastic IP y discos).
4. Billing al día siguiente, para confirmar el costo real.
5. **Decisión D12 (la toma el equipo):** mantener las instancias detenidas y las Elastic IP hasta que el profesor califique, si lo pide (≈ US$0.47 por día); luego liberar todo: `bash P1_dmz_infra.sh liberar-eip` y terminar las instancias desde la consola.
   Al liberar las Elastic IP, el DNS de `dernait.com` deja de apuntar a nuestra IP: avisar al dueño para que borre los registros `zenite` y `zenite-vpn`.

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| `InsufficientInstanceCapacity` al encender | No es un error de la cuenta: esa zona no tiene capacidad de ese tipo ahora. Encender de una en una con nombre, esperar 2 a 5 minutos y reintentar. Si persiste, con la instancia **detenida** cambiar el tipo (ej. `t3a.micro`) y anotarlo: `aws ec2 modify-instance-attribute --instance-id <id> --instance-type "{\"Value\": \"t3a.micro\"}"`. Consultar antes con el equipo. |
| **El dominio no resuelve** o resuelve a otra IP | `bash P1_dns_check.sh zenite.dernait.com 18.210.66.163`. Si responde `104.21.x` o `172.67.x`, el dueño del dominio activó el proxy de Cloudflare: pedir que ponga el registro en **nube gris (DNS only)**. Si resuelve a una IP distinta de la Elastic IP, pedir que lo corrija. Plan de emergencia: abrir el sitio por la IP `https://18.210.66.163` (el navegador avisará del certificado) y decirlo en voz alta. |
| **Elastic IP desasociada** (la web no responde por la IP pública) | `bash P1_dmz_infra.sh --validar` lo marca. Reasociar: `aws ec2 associate-address --allocation-id eipalloc-043ed2c86d162bff3 --instance-id i-06b59507240cfa8e7` (web) o `--allocation-id eipalloc-0e3c263d637223a5f --instance-id i-050e09727e2a06139` (VPN). Si alguien liberó la IP, la nueva será distinta: actualizar el registro DNS y el `.ovpn` de la VPN. |
| **Instancia sin estado 3/3** (`initializing` más de 8 a 10 min) | Esperar a que pasen los status checks antes de entrar por EICE. Si sigue, `aws ec2 reboot-instances --instance-ids <id>`; si no responde, detenerla, esperar `stopped` y encenderla de nuevo (conserva IP privada y Elastic IP). |
| `--validar` marca `[FALLA]` en una instancia | Leer la línea: `esperado` y `real`. Si dice `initializing`, esperar y repetir; si es una regla o un tag, avisar a P1 antes de tocar nada. |
| No conecta por EICE | Esperar a los status checks; comprobar que el EICE esté `create-complete` y que el SG de la instancia permita TCP/22 desde `zenite-eice`. |
| Aparece una entrada `0.0.0.0/0` no prevista en un SG | `--validar` la marca como «fuera de las excepciones D10». Quitarla (con aprobación de P3) antes de la demo. |
| La consola de AWS va lenta | Usar las capturas de `FaseFinal/evidencias/01_infra_dmz_dominio/` y los JSON de `FaseFinal/configuracion/` como respaldo y decirlo en voz alta. |
| Se pasó la demo y quedó algo encendido | `bash P1_costos.sh` dice qué; con las tres instancias nuevas y las de Fase 3 encendidas son ≈ US$1.5 por día más el NAT si existe (≈ US$1.20). |
