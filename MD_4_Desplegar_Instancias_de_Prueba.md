# Desplegar las instancias de prueba

## Objetivo

Crear las instancias EC2 mínimas necesarias para demostrar la conectividad exigida en Fase 2 y una regla de segmentación adicional.

Se crearán:

```text
zp-ventas-01 -> 10.20.0.10
zp-ventas-02 -> 10.20.0.11
zp-ti-01     -> 10.20.0.102
```

Las tres direcciones son válidas y no están dentro de las direcciones reservadas por AWS.

## Selección de instancia

Usa una imagen estándar de Linux soportada por EC2 Instance Connect, preferiblemente **Amazon Linux 2023**.

Para el tipo de instancia usa el tamaño más pequeño que sea razonable y que esté cubierto por los créditos o beneficios disponibles en la cuenta. `t3.micro` es adecuado para esta prueba si está disponible, pero no asumas que es gratuito en la cuenta.

No habilites IPv4 pública.

## Crear `zp-ventas-01`

En **EC2 > Instances > Launch instances**:

```text
Name: zp-ventas-01
AMI: Amazon Linux 2023
Instance type: t3.micro o equivalente pequeño
VPC: vpc-zenite-fase2
Subnet: subnet-zenite-ventas
Auto-assign public IP: Disable
Private IPv4: 10.20.0.10
Security Group: sg-zenite-ventas
Storage: mínimo razonable, por ejemplo 8 GiB gp3
```

En **Advanced details > User data** agrega:

```bash
#!/bin/bash
hostnamectl set-hostname zp-ventas-01
```

Etiquetas:

```text
Project = ZenitePrestige
Phase = Fase2
Role = Ventas
```

## Crear `zp-ventas-02`

Repite:

```text
Name: zp-ventas-02
Subnet: subnet-zenite-ventas
Private IPv4: 10.20.0.11
Security Group: sg-zenite-ventas
```

User data:

```bash
#!/bin/bash
hostnamectl set-hostname zp-ventas-02
```

Etiquetas:

```text
Project = ZenitePrestige
Phase = Fase2
Role = Ventas
```

## Crear `zp-ti-01`

Configura:

```text
Name: zp-ti-01
Subnet: subnet-zenite-ti
Private IPv4: 10.20.0.102
Security Group: sg-zenite-ti
Auto-assign public IP: Disable
```

User data:

```bash
#!/bin/bash
hostnamectl set-hostname zp-ti-01
```

Etiquetas:

```text
Project = ZenitePrestige
Phase = Fase2
Role = TI
```

## Verificar las tres instancias

En la lista de EC2 confirma:

| Instancia | Subred | IP privada | IPv4 pública |
|---|---|---:|---|
| `zp-ventas-01` | Ventas | `10.20.0.10` | Ninguna |
| `zp-ventas-02` | Ventas | `10.20.0.11` | Ninguna |
| `zp-ti-01` | TI | `10.20.0.102` | Ninguna |

Todas deben estar en:

```text
Running
Status checks: 2/2 passed
```

## Conectarse por EC2 Instance Connect Endpoint

Para cada instancia:

1. Selecciona la instancia.
2. Presiona **Connect**.
3. Selecciona **EC2 Instance Connect**.
4. Elige conexión mediante **EC2 Instance Connect Endpoint**.
5. Selecciona `eice-zenite-fase2`.
6. Usuario:
   - `ec2-user`
7. Conecta.

Si no conecta:

- Verifica que la instancia use Amazon Linux compatible.
- Verifica que el endpoint esté disponible.
- Confirma TCP/22 desde `sg-zenite-eice` hacia el Security Group de la instancia.
- Confirma que la instancia no tenga una NACL bloqueando SSH.
- No abras SSH a `0.0.0.0/0` para resolver el problema.

## Comandos de verificación

En cada instancia ejecuta:

```bash
hostname
ip -4 addr
ip route
cat /etc/os-release
```

El resultado debe mostrar la IP privada correcta.

En `zp-ventas-01`:

```text
10.20.0.10
```

En `zp-ventas-02`:

```text
10.20.0.11
```

En `zp-ti-01`:

```text
10.20.0.102
```

## Guardar información de cada host

Ejecuta en cada terminal:

```bash
{
  echo "=== FECHA ==="
  date
  echo "=== HOSTNAME ==="
  hostname
  echo "=== DIRECCIONES ==="
  ip -4 addr
  echo "=== RUTAS ==="
  ip route
  echo "=== SISTEMA ==="
  cat /etc/os-release
} | tee ~/info-fase2.txt
```

El archivo quedará disponible en cada instancia como:

```text
~/info-fase2.txt
```

Puede mostrarse durante la demo para demostrar que la IP no fue inventada en el reporte.

## Evidencia

Toma una captura de la vista de EC2 donde se vean simultáneamente:

- Nombres.
- Instance IDs.
- Estado.
- Private IPv4.
- Subnet ID.
- Public IPv4 vacía.

Guárdala como:

```text
evidencias/04_instancias/E07_Instancias_Privadas.png
```

También guarda una captura de `ip -4 addr` en `zp-ventas-01`:

```text
evidencias/04_instancias/E08_IP_Ventas01.png
```

## Resultado esperado

Al finalizar:

- Hay dos instancias en la subred de Ventas.
- Hay una instancia en la subred de TI.
- Ninguna depende de una IP pública.
- El equipo puede abrir terminal en las tres.
- Las IP privadas coinciden con el plan.
- El entorno está listo para las pruebas que se documentarán en el reporte.
