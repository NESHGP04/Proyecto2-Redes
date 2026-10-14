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
| E02 · E03 | `02_subredes/E02_Subredes_AWS.png` · `E03_Rutas_Interna.png` · `E03_Rutas_DMZ.png` · `E03_Rutas_Infra.png` |
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

## Parte 2 – Subredes y tablas de rutas (MD_2)

VPC de partida: `vpc-zenite-fase2` · `vpc-0e4c1d0b2314ab4df`. Las siete subredes van en **una sola AZ** (`us-east-1a`).

| Paso | Qué hacer |
|---|---|
| 1 | Consola en **N. Virginia** → CloudShell → subir `01_crear_vpc.sh` y `02_crear_subredes_rutas.sh`. |
| 2 | `bash 01_crear_vpc.sh --validar` — confirma que la VPC sigue correcta (no modifica nada). |
| 3 | `bash 02_crear_subredes_rutas.sh` — crea las 7 subredes y `rt-zenite-interna` / `rt-zenite-dmz` / `rt-zenite-infra`, asocia cada subred, valida y genera el registro. Debe terminar en `RESULTADO: todo correcto.` |
| 4 | Consola → VPC → *Subnets*, filtrar por la VPC y ordenar por IPv4 CIDR (columnas Name, Subnet ID, VPC, IPv4 CIDR, Availability Zone) → `evidencias/02_subredes/E02_Subredes_AWS.png`. |
| 5 | Consola → VPC → *Route tables*, filtrar por la VPC, seleccionar cada tabla con el panel de detalles en la pestaña *Routes* (la columna *Explicit subnet associations* muestra las asociaciones) → `evidencias/02_subredes/E03_Rutas_Interna.png`, `E03_Rutas_DMZ.png`, `E03_Rutas_Infra.png`. |
| 6 | Descargar de `~/fase2-config/` a `configuracion/`: `subnets.json`, `route-tables.json`, `subredes-validacion.txt` y `segmentacion.md` (reemplaza la plantilla con los IDs reales). Si *Download file* no funciona en el panel inferior, abrir CloudShell en pantalla completa o usar `cat` y copiar. |

Para AZ distinta: `AZ=us-east-1b bash 02_crear_subredes_rutas.sh`. El script se detiene sin cambiar nada si encuentra subredes
fuera del plan, en otra AZ o sobre `10.20.0.160/27` / `10.20.0.192/26`.

Equivalente manual: *Subnets → Create subnet* (VPC `vpc-zenite-fase2`, AZ `us-east-1a`, nombre y CIDR de la tabla de
segmentación, etiquetas `Project`, `Phase`, `Environment`) y *Route tables → Create route table* (misma VPC) → *Subnet
associations → Edit*. No agregar rutas: cada tabla queda solo con `10.20.0.0/24 → local`.

## Parte 4 – Instancias de prueba (MD_4)

Parte de lo entregado en MD_3: Security Groups `zenite-ventas` (`sg-01f1eb855a2b85df7`), `zenite-ti` (`sg-0e73e9942dd403016`)
y `zenite-eice` (`sg-0697e7f5646e28ab4`, solo para el endpoint), y `eice-zenite-fase2` (`eice-0f41a9a04ed4dc3e2`) en
`subnet-zenite-infra`. Las instancias usan Amazon Linux 2023, sin IPv4 pública y sin llave SSH.

| Paso | Qué hacer |
|---|---|
| 1 | Consola en **N. Virginia** → CloudShell → subir `04_crear_instancias.sh`. |
| 2 | `bash 04_crear_instancias.sh` — comprueba subredes, Security Groups, EICE e IPs libres; crea `zp-ventas-01` (`10.20.0.10`), `zp-ventas-02` (`10.20.0.11`) y `zp-ti-01` (`10.20.0.102`); espera los status checks 2/2 y valida. Debe terminar en `RESULTADO: todo correcto.` Si los checks tardan, repetir con `--validar`. |
| 3 | Consola → EC2 → *Instances*, columnas Name, Instance ID, Instance state, Private IPv4, Subnet ID y Public IPv4 (vacía) → `evidencias/04_instancias/E07_Instancias_Privadas.png`. |
| 4 | En cada instancia: *Connect* → *EC2 Instance Connect* → *Connect using EC2 Instance Connect Endpoint* → `eice-zenite-fase2`, usuario `ec2-user`. Ejecutar el bloque de MD_4 que guarda `~/info-fase2.txt`. En `zp-ventas-01`, captura de `ip -4 addr` → `evidencias/04_instancias/E08_IP_Ventas01.png`. |
| 5 | Descargar de `~/fase2-config/` a `configuracion/`: `instances.json` e `instancias-validacion.txt`. |

Otro tipo de instancia: `TIPO=t4g.micro bash 04_crear_instancias.sh` (la AMI se elige según la arquitectura). El script
avisa si el tipo no es Free Tier en la cuenta y se detiene sin crear nada si falta el EICE, un Security Group o una subred,
o si alguna IP del plan ya está en uso. Desde CloudShell también se puede entrar a una instancia con
`aws ec2-instance-connect ssh --instance-id <id> --os-user ec2-user --connection-type eice`.

Equivalente manual: *EC2 → Launch instances* → nombre, Amazon Linux 2023, `t3.micro`, sin key pair → *Network settings →
Edit*: VPC `vpc-zenite-fase2`, subred, *Auto-assign public IP: Disable*, Security Group existente → *Advanced network
configuration → Primary IP* → *Advanced details*: *Metadata version: V2 only*, *Credit specification: Standard* y el user
data de MD_4 → etiquetas `Project`, `Phase`, `Environment`, `Owner`, `Role`.

Si EC2 Instance Connect no conecta: esperar a 2/2, revisar que `zenite-ventas` / `zenite-ti` permitan TCP/22 desde
`zenite-eice` (la validación lo comprueba) y que el usuario IAM tenga `ec2-instance-connect:OpenTunnel`. No abrir SSH a `0.0.0.0/0`.

## Control de costos y seguridad

- En las partes 1 y 2 **no** debe existir ninguna EC2, NAT Gateway, Elastic IP, Internet Gateway ni VPN Site-to-Site (`00_verificar_entorno.sh` y `02_crear_subredes_rutas.sh` lo comprueban).
- Para administrar las instancias privadas se usa EC2 Instance Connect Endpoint (sin IPv4 pública y sin NAT Gateway).
- No subir Access Keys, Secret Keys, Session Tokens, contraseñas ni llaves SSH (el `.gitignore` de la raíz bloquea los casos comunes).
  Las variables sensibles están listadas, sin valores, en `.env.example` (raíz). Para usar los scripts fuera de CloudShell:
  `cp .env.example .env` y llenar `.env`, que está ignorado por git. En CloudShell no hace falta.
- Al terminar cada sesión: detener las instancias (`Stop`) y revisar Billing. Desde CloudShell:
  ```bash
  aws ec2 stop-instances --region us-east-1 --instance-ids $(aws ec2 describe-instances --region us-east-1 \
    --filters "Name=tag:Phase,Values=Fase2" "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" --output text)
  ```
  Detenidas no cobran cómputo, pero el disco EBS (8 GiB por instancia) sí. Para volver: `bash 04_crear_instancias.sh` las enciende.
- La consola web usa usuario y contraseña de IAM; esa contraseña no sirve para la AWS CLI y no se guarda en el repositorio
  (`.gitignore` bloquea `*credentials*.csv`). En CloudShell no hacen falta Access Keys.
