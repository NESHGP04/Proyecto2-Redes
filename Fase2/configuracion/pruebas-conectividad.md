# Pruebas de conectividad — Fase 2

## Entorno

- Región AWS: us-east-1 (N. Virginia).
- VPC: vpc-0e4c1d0b2314ab4df.
- CIDR de la VPC: 10.20.0.0/24.
- Pruebas realizadas mediante ICMP entre instancias privadas.

## Resultados

| Origen | Destino | Esperado | Resultado observado | Evidencia |
|---|---|---|---|---|
| Ventas 01 — 10.20.0.10 | Ventas 02 — 10.20.0.11 | Permitido | 4 enviados, 4 recibidos; 0 % de pérdida | E09 |
| Ventas 02 — 10.20.0.11 | Ventas 01 — 10.20.0.10 | Permitido | 4 enviados, 4 recibidos; 0 % de pérdida | E10 |
| TI 01 — 10.20.0.102 | Ventas 01 — 10.20.0.10 | Permitido | 4 enviados, 4 recibidos; 0 % de pérdida | E11 |
| Ventas 01 — 10.20.0.10 | TI 01 — 10.20.0.102 | Bloqueado | 4 enviados, 0 recibidos; 100 % de pérdida | E12 |

Las evidencias textuales adicionales muestran conectividad desde TI hacia
Ventas 02 y ausencia de respuestas desde Ventas 02 hacia TI.

Los TXT y las capturas contienen ejecuciones distintas; sus tiempos de
respuesta no deben presentarse como si pertenecieran a una misma ejecución.

## Rutas locales verificadas

| Origen | Destino | Interfaz | Gateway |
|---|---|---|---|
| 10.20.0.10 | 10.20.0.11 | ens5 | Ruta directa |
| 10.20.0.10 | 10.20.0.102 | ens5 | 10.20.0.1 |
| 10.20.0.102 | 10.20.0.10 | ens5 | 10.20.0.97 |

## Segmentación

Las dos instancias de Ventas tienen asignado zenite-ventas, que permite
ICMP desde zenite-ventas y zenite-ti.

La instancia de TI tiene asignado zenite-ti, que permite ICMP desde
zenite-ti, pero no desde zenite-ventas.

Los resultados observados son coherentes con estas reglas. Estas pruebas
validan el comportamiento de ICMP para los pares evaluados; no demuestran
por sí solas todas las restricciones para otros protocolos o segmentos.

## Configuración exportada

- vpc.json: 1 VPC.
- subnets.json: 7 subredes.
- route-tables.json: 4 tablas de rutas.
- security-groups.json: 4 Security Groups.
- instances.json: 3 instancias.
- instance-connect-endpoints.json: 1 endpoint.

Los JSON documentan la configuración consultada; no constituyen una
plantilla de despliegue automático.

## Observaciones pendientes

Las tablas exportadas solo muestran la ruta local 10.20.0.0/24.
No muestran rutas de salida a Internet. Si esta fase exige dicha salida,
deberá implementarse y verificarse por separado.
