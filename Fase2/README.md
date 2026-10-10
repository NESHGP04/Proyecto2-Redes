# Fase 2 – Implementación de la red en la nube (AWS)

**CC3067 Redes · UVG · Sección 30 · Zenite Prestige Guatemala**
**Entrega:** 23 de octubre de 2026 · Reporte + capturas de conectividad + archivos de configuración + presentación y demo en vivo.

Prototipo de la segmentación de Fase 1 en AWS: una VPC `10.20.0.0/24` con las siete subredes VLSM y una prueba de
conectividad entre instancias (Ventas ↔ Ventas, TI → Ventas permitido, Ventas → TI bloqueado).
No se encienden los servidores productivos de Fase 1; solo lo necesario para demostrar segmentación y conectividad.

## Parámetros fijos (no cambiar)

| Parámetro | Valor |
|---|---|
| Proveedor / región | AWS · `us-east-1` (N. Virginia) |
| VPC | `vpc-zenite-fase2` · `10.20.0.0/24` |
| Etiquetas | `Project=ZenitePrestige` · `Phase=Fase2` · `Environment=Prototype` · `Owner=Grupo30` |

## Segmentación (heredada de Fase 1)

AWS reserva las cuatro primeras direcciones y la última de cada subred. La dirección que en el diseño aparece como
"gateway" (`.1`, `.33`, …) es el **VPC Router** de AWS: no es configurable ni asignable a una instancia.

| Segmento | Nombre AWS | CIDR | VPC Router | Asignable a instancias |
|---|---|---|---|---|
| Ventas | `subnet-zenite-ventas` | `10.20.0.0/27` | `10.20.0.1` | `10.20.0.4 – .30` |
| Visitantes | `subnet-zenite-visitantes` | `10.20.0.32/27` | `10.20.0.33` | `10.20.0.36 – .62` |
| Servidores | `subnet-zenite-servidores` | `10.20.0.64/27` | `10.20.0.65` | `10.20.0.68 – .94` |
| TI | `subnet-zenite-ti` | `10.20.0.96/28` | `10.20.0.97` | `10.20.0.100 – .110` |
| DMZ | `subnet-zenite-dmz` | `10.20.0.112/28` | `10.20.0.113` | `10.20.0.116 – .126` |
| VPN | `subnet-zenite-vpn` | `10.20.0.128/28` | `10.20.0.129` | `10.20.0.132 – .142` |
| Infraestructura | `subnet-zenite-infra` | `10.20.0.144/28` | `10.20.0.145` | `10.20.0.148 – .158` |
| Reserva A / B | *(no se crean)* | `10.20.0.160/27` · `10.20.0.192/26` | – | crecimiento futuro |

En la DMZ, `.114` y `.115` son de AWS: el web público queda en `10.20.0.116` y el proxy TLS en `10.20.0.117`.

## Estructura

```
Fase2/
├── evidencias/
│   ├── 01_vpc/          E01
│   ├── 02_subredes/     E02, E03
│   ├── 03_seguridad/    E04, E05, E06
│   ├── 04_instancias/   E07, E08
│   └── 05_pruebas/      E09 – E12
├── configuracion/       scripts de AWS CLI + JSON exportados (vpc, subnets, route-tables, security-groups, instances, eice)
├── reporte/             secciones del reporte
├── bitacora.md
└── README.md
```

## Nombres de recursos y de evidencias

Los MD_2 a MD_5 usan estos nombres; son los que valen (los nombres de ejemplo del MD_1 son solo ilustrativos).

| Recurso | Nombre |
|---|---|
| Route tables | `rt-zenite-interna` · `rt-zenite-dmz` · `rt-zenite-infra` |
| Security Groups | `sg-zenite-ventas` · `sg-zenite-ti` · `sg-zenite-eice` |
| EC2 Instance Connect Endpoint | `eice-zenite-fase2` (en `subnet-zenite-infra`) |
| Instancias | `zp-ventas-01` `10.20.0.10` · `zp-ventas-02` `10.20.0.11` · `zp-ti-01` `10.20.0.102` |

| Evidencia | Archivo |
|---|---|
| E01 | `01_vpc/E01_VPC_CIDR.png` |
| E02 · E03 | `02_subredes/E02_Subredes_AWS.png` · `E03_Rutas.png` |
| E04 · E05 · E06 | `03_seguridad/E04_SG_Ventas.png` · `E05_SG_TI.png` · `E06_EICE.png` |
| E07 · E08 | `04_instancias/E07_Instancias_Privadas.png` · `E08_IP_Ventas01.png` |
| E09 – E12 | `05_pruebas/E09_Ping_Ventas01_a_Ventas02_OK.png` · `E10_Ping_Ventas02_a_Ventas01_OK.png` · `E11_Ping_TI_a_Ventas_OK.png` · `E12_Ping_Ventas_a_TI_BLOQUEADO.png` |

## Parte 1 – AWS y VPC (MD_1)

Scripts en [configuracion/](configuracion/), pensados para **AWS CloudShell** (sin credenciales en el repo):

| Paso | Qué hacer |
|---|---|
| 1 | Consola AWS → región **US East (N. Virginia)** → abrir CloudShell. Revisar Billing (créditos y gasto). |
| 2 | `bash 00_verificar_entorno.sh` — solo lectura: identidad, VPC existentes y recursos con costo. |
| 3 | `bash 01_crear_vpc.sh` — crea (o reutiliza) `vpc-zenite-fase2`, activa DNS resolution y DNS hostnames, etiqueta y valida. |
| 4 | Consola → VPC → *Your VPCs*: capturar nombre, VPC ID, CIDR, región y estado `Available` → `evidencias/01_vpc/E01_VPC_CIDR.png`. |
| 5 | Descargar `~/fase2-config/vpc.json` y `vpc-validacion.txt` a `configuracion/`. |

Equivalente manual en la consola: VPC → *Create VPC* → *VPC only* → nombre `vpc-zenite-fase2`, IPv4 `10.20.0.0/24`,
sin IPv6, tenancy Default → *Actions → Edit VPC settings*: DNS resolution y DNS hostnames habilitados → etiquetas.

## Control de costos y seguridad

- En esta parte **no** debe existir ninguna EC2, NAT Gateway, Elastic IP ni VPN Site-to-Site (`00_verificar_entorno.sh` lo comprueba).
- Para administrar las instancias privadas se usa EC2 Instance Connect Endpoint (sin IPv4 pública y sin NAT Gateway).
- No subir Access Keys, Secret Keys, Session Tokens, contraseñas ni llaves SSH (el `.gitignore` de la raíz bloquea los casos comunes).
- Al terminar cada sesión: detener las instancias (`Stop`) y revisar Billing.
