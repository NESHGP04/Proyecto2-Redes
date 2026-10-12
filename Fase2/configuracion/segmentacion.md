# Registro de implementación: subredes y tablas de rutas

IDs tomados de la salida de `02_crear_subredes_rutas.sh` en AWS CloudShell, validación del 2026-10-12 07:28 UTC.
VPC `vpc-zenite-fase2` · `vpc-0e4c1d0b2314ab4df` · `10.20.0.0/24` · región `us-east-1`.

| Nombre lógico | CIDR | Subnet ID | Route Table | Route Table ID | Availability Zone | Asignables | Uso |
|---|---|---|---|---|---|---|---|
| `subnet-zenite-ventas` | `10.20.0.0/27` | `subnet-0234dd20474eef1aa` | `rt-zenite-interna` | `rtb-003c14fc932b0a079` | `us-east-1a` | `10.20.0.4 – 10.20.0.30` | Prueba de usuarios de Ventas |
| `subnet-zenite-visitantes` | `10.20.0.32/27` | `subnet-0edb31ab5f88d89fb` | `rt-zenite-interna` | `rtb-003c14fc932b0a079` | `us-east-1a` | `10.20.0.36 – 10.20.0.62` | Segmento de invitados |
| `subnet-zenite-servidores` | `10.20.0.64/27` | `subnet-0990205c298b0635d` | `rt-zenite-interna` | `rtb-003c14fc932b0a079` | `us-east-1a` | `10.20.0.68 – 10.20.0.94` | Servicios internos |
| `subnet-zenite-ti` | `10.20.0.96/28` | `subnet-0688bbf577464f544` | `rt-zenite-interna` | `rtb-003c14fc932b0a079` | `us-east-1a` | `10.20.0.100 – 10.20.0.110` | Administración |
| `subnet-zenite-dmz` | `10.20.0.112/28` | `subnet-0d29453584ea726c0` | `rt-zenite-dmz` | `rtb-003940fecf347d53d` | `us-east-1a` | `10.20.0.116 – 10.20.0.126` | Servicios publicados |
| `subnet-zenite-vpn` | `10.20.0.128/28` | `subnet-061f6bea484702eec` | `rt-zenite-interna` | `rtb-003c14fc932b0a079` | `us-east-1a` | `10.20.0.132 – 10.20.0.142` | Segmento lógico de VPN |
| `subnet-zenite-infra` | `10.20.0.144/28` | `subnet-043e821cc9ee7c765` | `rt-zenite-infra` | `rtb-02a9c591ec4299135` | `us-east-1a` | `10.20.0.148 – 10.20.0.158` | Gestión e infraestructura |

## Tablas de rutas

| Route table | Route Table ID | Rutas | Subredes asociadas |
|---|---|---|---|
| `rt-zenite-interna` | `rtb-003c14fc932b0a079` | `10.20.0.0/24 -> local` | `subnet-0234dd20474eef1aa` (ventas)<br>`subnet-0edb31ab5f88d89fb` (visitantes)<br>`subnet-0990205c298b0635d` (servidores)<br>`subnet-0688bbf577464f544` (ti)<br>`subnet-061f6bea484702eec` (vpn) |
| `rt-zenite-dmz` | `rtb-003940fecf347d53d` | `10.20.0.0/24 -> local` | `subnet-0d29453584ea726c0` (dmz) |
| `rt-zenite-infra` | `rtb-02a9c591ec4299135` | `10.20.0.0/24 -> local` | `subnet-043e821cc9ee7c765` (infra) |

La tabla principal de la VPC (`rtb-0018789e96aaf0a54`, sin nombre) la crea AWS automáticamente; también tiene solo la ruta
local y ninguna subred depende de ella (las siete tienen asociación explícita).

Bloques de reserva sin usar: `10.20.0.160/27` (Reserva A) y `10.20.0.192/26` (Reserva B).
No hay Internet Gateway, NAT Gateway, Elastic IP ni instancias en este paso.
