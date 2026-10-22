# Fase 3 – Plan de encendido para la demo y guion de la parte de infraestructura (P1)

La demo en vivo necesita el NAT y las instancias encendidos, pero fuera de la demo todo debe estar apagado (la cuenta no tiene créditos). Este plan dice
**cuánto antes hay que encender**, qué comprobar y cómo mostrar la parte de infraestructura.

## Tiempos observados (sesión real del 21 de octubre)

| Paso | Duración observada |
|---|---|
| `bash P1_gateways.sh crear` hasta el `RESULTADO: todo correcto.` (el NAT tarda en estar `available`) | ≈ 2 min (21:59:11 → 22:01:15 UTC) |
| `bash P1_instancias.sh crear` (cuatro instancias nuevas, incluye esperar los status checks) | ≈ 5 min |
| `bash P1_instancias.sh encender` sobre instancias ya creadas, hasta 3/3 checks | de 3 a 5 min (una instancia seguía en `Initializing` varios minutos después) |
| Conectarse por EC2 Instance Connect Endpoint | segundos |
| `bash P1_gateways.sh destruir` | menos de 1 min |

**Encender todo lleva unos 10 minutos.** Conviene empezar **20 a 30 minutos antes** de la presentación para tener margen. El NAT encendido ese tiempo cuesta centavos
(≈ US$0.05 por hora).

## Lista de verificación previa (T − 30 min)

1. **Billing:** revisar créditos y gasto (la cuenta no tiene créditos activos). Si el gasto del mes es mayor al esperado, averiguar el motivo antes de encender nada.
2. **Estado de partida (solo lectura):** `bash P1_estado_inicial.sh`. Debe mostrar 0 instancias encendidas, 0 NAT y 0 Elastic IP en todas las regiones.
3. **NAT:** `bash P1_gateways.sh crear` → `RESULTADO: todo correcto.`
4. **Instancias:** encender solo las que usará la demo, por nombre. Por ejemplo, `bash P1_instancias.sh encender zp-ventas-01 zp-ti-01 zp-ntp-01 zp-ldap-01 zp-intranet-01 zp-visitantes-01`.
5. **Validar:** `bash P1_instancias.sh --validar` (instancias nuevas) y `bash P1_gateways.sh --validar`. Esperar 3/3 checks en las instancias.
6. **Ensayo:** conectar por EICE a cada instancia que se usará y correr una vez todas las pruebas del guion de la demo. Anotar los Instance IDs y las IP a mano.
7. **Congelar:** no cambiar reglas ni scripts en los 5 minutos anteriores.
8. **Respaldo:** tener abiertas las capturas `FASE3_INF-01` a `INF-04` y los JSON `*_encendido.json`, por si la consola de AWS va lenta.

## Guion de la parte de infraestructura (≈ 2 min)

1. **Consola → VPC → Internet gateways:** `igw-zenite-fase3`, `Attached` a `vpc-zenite-fase2`.
2. **VPC → NAT gateways:** `nat-zenite-fase3`, `Available`, en `subnet-zenite-infra`, IP privada `10.20.0.148` y su Elastic IP. Anotar la Elastic IP.
3. **VPC → Route tables:**
   - `rt-zenite-interna`: `0.0.0.0/0 → nat-...` (Ventas, Visitantes, Servidores, TI y VPN salen por el NAT).
   - `rt-zenite-infra`: `0.0.0.0/0 → igw-...` (el NAT sale por el Internet Gateway).
   - `rt-zenite-dmz`: solo la ruta local.
4. **EC2 → Instances:** las instancias `zp-*` con IP privada y **sin IPv4 pública**.
5. **Prueba del NAT:** terminal por EICE en `zp-visitantes-01` y correr
   ```text
   uname -n; curl -sI https://aws.amazon.com | head -3; curl -s https://checkip.amazonaws.com; date
   ```
   La IP que devuelve `checkip` es la **Elastic IP del NAT** del paso 2: el tráfico privado sale traducido por el NAT.
6. **Costos:** mencionar que el NAT se enciende solo en las sesiones de trabajo y se destruye al terminar; mostrar `gateways-sesiones.log` con las horas.

## Después de la demo

1. `bash P1_instancias.sh detener` (todas las `zp-*`).
2. `bash P1_gateways.sh destruir` (muestra quién lo creó y hace cuánto) y luego `bash P1_gateways.sh --validar-apagado` → `RESULTADO: todo correcto.`
3. `bash P1_estado_inicial.sh`: 0 instancias encendidas, 0 NAT, 0 Elastic IP.
4. Billing al día siguiente, para confirmar el costo real.

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| `crear` se detiene con `ERROR` | Leer el mensaje: el script no deja nada a medias; volver a correrlo no duplica recursos. Causas posibles: IP del NAT ocupada (`NAT_IP=...`), ruta por defecto ajena en una route table, permisos. |
| `PendingVerification` al lanzar instancias | Esperar unos minutos y reintentar; ya pasó en Fase 2. |
| `UnauthorizedOperation` | Falta un permiso en el usuario IAM; pedirlo a la dueña de la cuenta. |
| No conecta por EICE | Esperar a los status checks 3/3; comprobar que el EICE esté `create-complete` y que el Security Group de la instancia permita TCP/22 desde `zenite-eice`. |
| Una instancia sin Internet | `bash P1_gateways.sh --validar`; si el NAT no está `available` o falta la ruta de `rt-zenite-interna`, volver a correr `crear`. |
| La consola de AWS va lenta | Usar las capturas `INF-01` a `INF-04` y los JSON `*_encendido.json` como respaldo y decirlo en voz alta. |
| Se pasó la demo y el NAT sigue encendido | `bash P1_gateways.sh destruir`. Un NAT olvidado cuesta ≈ US$1.20 por día. |
