# Entrega para el reporte (instancias de prueba y costos)

Respuestas a lo pedido para el reporte. Las capturas de esta carpeta son copias de `../evidencias/04_instancias/`; el
detalle completo está en `../reporte/04_instancias_de_prueba.md` y `../reporte/05_pruebas_de_conectividad.md`.

## 1. E07 – Instancias privadas

La tabla de EC2 no muestra en una sola pantalla el nombre y la IP privada / subred, así que la E07 quedó en dos capturas
más un detalle de apoyo:

| Archivo | Qué muestra |
|---|---|
| `E07_Instancias_Privadas.png` | Las 3 instancias: Name, Instance ID, `Running`, `t3.micro`, `3/3 checks passed`, `us-east-1a`, Public IPv4 DNS y Public IPv4 vacías. |
| `E07_Instancias_Privadas_IP_Subred.png` | La misma tabla desplazada: Security Group, IP privada (`10.20.0.10`, `10.20.0.11`, `10.20.0.102`) y Subnet ID. |
| `E07_Detalle_zp-ventas-01.png` | Detalle de `zp-ventas-01`: IP privada `10.20.0.10`, sin IPv4 pública ni Elastic IP, subred `subnet-zenite-ventas`, IMDSv2 `Required`. |

## 2. E08 – IP de zp-ventas-01

`E08_IP_Ventas01.png`: terminal de `zp-ventas-01` abierta por EC2 Instance Connect Endpoint; `ip -4 addr` muestra
`inet 10.20.0.10/27` en `ens5`.

## 3. Instance IDs y tipo de instancia

Tipo: **`t3.micro`** en las tres (Amazon Linux 2023, AMI `ami-08c982207dfbf2b27`, `us-east-1a`).

| Instancia | Instance ID | IP privada | Subred |
|---|---|---|---|
| `zp-ventas-01` | `i-0f3bd7b0615933e00` | `10.20.0.10` | `subnet-zenite-ventas` (`subnet-0234dd20474eef1aa`) |
| `zp-ventas-02` | `i-05a7f9ee1a6e93000` | `10.20.0.11` | `subnet-zenite-ventas` (`subnet-0234dd20474eef1aa`) |
| `zp-ti-01` | `i-0378a8624df39958b` | `10.20.0.102` | `subnet-zenite-ti` (`subnet-0688bbf577464f544`) |

## 4. Costos

**Horas encendidas** (hora de lanzamiento y de detención según AWS):

| Instancia | Encendida (UTC) | Detenida (UTC) | Tiempo |
|---|---|---|---|
| `zp-ventas-01` | 2026-10-14 23:46:15 | 2026-10-15 00:41:34 | 55 min |
| `zp-ventas-02` | 2026-10-14 23:46:21 | 2026-10-15 00:41:34 | 55 min |
| `zp-ti-01` | 2026-10-15 00:01:26 | 2026-10-15 00:41:34 | 40 min |
| **Total** | | | **≈ 2.5 horas-instancia** |

En hora de Guatemala: Ventas de 17:46 a 18:41 y TI de 18:01 a 18:41 del 14 de octubre. `t3.micro` aparece como Free Tier en
la cuenta; como referencia, a precio On-Demand (USD 0.0104/h en `us-east-1`) serían unos USD 0.03. Detenidas no cobran
cómputo, solo los 3 discos EBS de 8 GiB gp3.

**Confirmación de recursos** (consultado con la AWS CLI después de detener las instancias, 2026-10-15 00:41 UTC):

| Recurso | Cantidad |
|---|---|
| Instancias en `running` (us-east-1) | 0 |
| NAT Gateway | 0 |
| Elastic IP | 0 |
| Internet Gateway en `vpc-zenite-fase2` | 0 |

**Captura de Billing: pendiente.** El usuario IAM `Ernesto` no tiene permisos de Billing ni de Cost Explorer
(`AccessDeniedException`); la tiene que tomar Marinés con la cuenta dueña.
