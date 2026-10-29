# Seguridad: Security Groups, Network ACL, SSH y hardening

*Sección del reporte de Fase 3 · Persona 5 · control de tráfico entre subredes, acceso administrativo y endurecimiento de las siete instancias.*

## 1. Objetivo de esta parte

- Cumplir las reglas de seguridad de la Fase 3: SSH a las instancias, Visitantes solo hacia Internet, TI hacia todas las subredes (y ninguna hacia TI), Intranet accesible desde las demás subredes excepto Visitantes y nunca desde Internet.
- Hacerlo con dos capas independientes, **Security Group** (con estado, por grupo de origen) y **Network ACL** (sin estado, por subred), y demostrar cada regla con una prueba permitida y una bloqueada.
- Endurecer las instancias: puertos abiertos antes y después, `sshd` sin contraseña ni root, servicios innecesarios desactivados y ninguna entrada desde `0.0.0.0/0`.

*Horas de Guatemala (UTC−6); las capturas muestran UTC, 6 horas más.*

**Estado de validación:** reglas aplicadas y probadas con evidencia real el 29 de octubre de 2026 (SEG-01 a SEG-06 y HARD-01 a HARD-03). HARD-04 se comprueba con `P5_security_groups.sh --validar` (ver sección 6). Las pruebas WEB-01 a WEB-05 (P4) y LDAP-05 (P3) dependen de las mismas reglas y las registran sus responsables.

## 2. Recursos y herramientas

| Elemento | Detalle |
|---|---|
| Región / VPC | `us-east-1` · `vpc-zenite-fase2` (`vpc-0e4c1d0b2314ab4df`, `10.20.0.0/24`) |
| Security Groups | `zenite-eice`, `zenite-ventas`, `zenite-ti`, `zenite-servidores`, `zenite-visitantes` |
| Network ACL nuevas | `acl-zenite-visitantes` (`acl-0f4182c4588b10b3c`) y `acl-zenite-ti` (`acl-0d1325ce978d9c23e`) |
| ACL predeterminada | `acl-067acfb0422ab4b7e`: conserva Ventas, Servidores, VPN, DMZ e Infra |
| Acceso administrativo | EC2 Instance Connect Endpoint `eice-zenite-fase2` (`10.20.0.150`, subred Infra `10.20.0.144/28`); sin IP pública en ninguna instancia |
| Scripts | `Fase3/configuracion/P5_security_groups.sh`, `P5_acls.sh` y `P5_hardening.sh`, todos con `--validar` (solo lectura) y `--revertir` |
| Tabla de reglas | `Fase3/configuracion/P5_reglas_seguridad.md` |
| Evidencias | `Fase3/evidencias/05_seguridad/` |

## 3. Decisiones

| Decisión | Justificación |
|---|---|
| Reglas de Security Group siempre por grupo de origen | No dependen de las IP; cualquier instancia nueva del grupo hereda la regla. |
| Egress de los Security Groups abierto | Decisión del equipo: la restricción hacia lo interno la hace la ACL. `zenite-eice` conserva su salida limitada a TCP 22 hacia `10.20.0.0/24`. |
| Sin firewall dentro del sistema operativo | Dos capas de AWS son suficientes para el alcance de la fase; menos riesgo de perder el acceso. |
| ACL propia solo para Visitantes y TI (D2) | Son las dos subredes con una denegación explícita. Ventas y Servidores se controlan con Security Group; menos riesgo de cortar el EICE. |
| TI sin salida a Internet por ACL (D1) | TI es la subred administrativa. `nmap` se instaló en `zp-ti-01` **antes** de aplicar su ACL, con el NAT encendido. |
| No abrir TCP 443 (D3) | Ningún servicio lo escucha. La Intranet se implementó en HTTP 80 (P4); la Fase 1 mencionaba HTTPS. |
| TI puede entrar por SSH e ICMP a Visitantes (D4) | La regla dice que TI conecta a todas las subredes. |
| La regla de TCP 22 desde el EICE va primero en cada ACL | Las ACL se evalúan por número y la primera coincidencia gana; la denegación de `10.20.0.0/24` queda después, así el EICE (`10.20.0.144/28`) nunca se corta. |
| Se aplica una ACL a la vez, con rollback listo | Un error en una ACL puede dejar la instancia inaccesible; se comprobó la entrada por EICE tras cada cambio. |
| `sshd` endurecido con un archivo propio | `/etc/ssh/sshd_config.d/00-zenite-hardening.conf` no edita `sshd_config`, se valida con `sshd -t` y se recarga con `reload` (no corta sesiones). |

## 4. Implementación

### 4.1 Diagnóstico inicial (HARD-01 «antes»)

Solo lectura desde CloudShell: 15 reglas de entrada, sin ninguna desde `0.0.0.0/0`; egress abierto salvo `zenite-eice`; una única ACL, la predeterminada, asociada a las siete subredes y que permite todo; `rt-zenite-interna` solo con ruta local (sin NAT) y sin IP públicas. Dentro de las instancias, `ss -tulpn` mostró únicamente TCP 22 más los servicios propios de cada una (UDP 123 en NTP, TCP 389 y 636 en LDAP, TCP 80 en Intranet) y los UDP locales de DHCP y `chronyd`.

Anotación honesta: la regla UDP 123 de `zenite-servidores` (S-02) la pidió P2 y se aplicó **antes** del diagnóstico, por lo que el «antes» del Security Group es parcial.

### 4.2 Security Groups (`P5_security_groups.sh`)

Se agregaron 8 reglas de entrada, sin tocar las de P1, P2 ni P3 (que el script comprueba):

| ID | Destino | Origen | Servicio |
|---|---|---|---|
| S-04 | `zenite-servidores` | `zenite-ventas`, `zenite-ti`, `zenite-servidores` | TCP 80 (Intranet) |
| S-05 | `zenite-servidores` | `zenite-ti` | TCP 22 |
| S-06 | `zenite-servidores` | `zenite-ti` | ICMP |
| S-07 | `zenite-ventas` | `zenite-ti` | TCP 22 |
| S-08 | `zenite-visitantes` | `zenite-ti` | TCP 22 e ICMP |

Quedan sin cambios: SSH desde `zenite-eice` en todos (S-01), UDP 123 (S-02) y TCP 389 y 636 desde Ventas y TI (S-03, P3). `zenite-ti` no admite ningún origen salvo el EICE y TI: **nadie inicia hacia TI**. Ninguna regla de entrada usa `0.0.0.0/0` (S-10).

### 4.3 Network ACL (`P5_acls.sh`)

`acl-zenite-visitantes` (14 reglas):

| Dirección | Regla | Origen / destino | Servicio | Acción |
|---|---|---|---|---|
| Entrada | 100 / 110 | `10.20.0.144/28` (EICE) / `10.20.0.96/28` (TI) | TCP 22 | Permitir |
| Entrada | 120 | TI | ICMP | Permitir |
| Entrada | **200** | `10.20.0.0/24` | todo | **Denegar** |
| Entrada | 300 / 310 | `0.0.0.0/0` | TCP / UDP 1024-65535 (retorno) | Permitir |
| Salida | 100 / 110 | EICE / TI | TCP 1024-65535 (retorno SSH) | Permitir |
| Salida | 120 | TI | ICMP | Permitir |
| Salida | **200** | `10.20.0.0/24` | todo | **Denegar** |
| Salida | 300 / 310 | `0.0.0.0/0` | TCP 80 / 443 | Permitir |
| Salida | 320 / 330 | `0.0.0.0/0` | DNS TCP / UDP 53 | Permitir |

`acl-zenite-ti` (5 reglas): entrada 100 TCP 22 desde el EICE; 110 y 120 retorno TCP/UDP 1024-65535 desde la VPC; 130 solo ICMP **echo reply**; salida 100 todo hacia `10.20.0.0/24`. Sin regla hacia Internet.

El script crea la ACL, agrega las reglas y **solo después** asocia la subred, guarda el estado antes y después en `~/fase3-config/p5-acl-estado-*.json` y valida cada regla. `--revertir` vuelve la subred a la ACL predeterminada y borra la nueva.

### 4.4 Hardening (`P5_hardening.sh`)

Se ejecuta dentro de cada instancia: crea el archivo de `sshd` con `PermitRootLogin no`, `X11Forwarding no` y `MaxAuthTries 3` (ya estaban bien `PasswordAuthentication no`, `PubkeyAuthentication yes` y `KbdInteractiveAuthentication no`), y desactiva los servicios innecesarios: `atd`, `gssproxy` y `libstoragemgmt` en Amazon Linux, y `ModemManager`, `multipathd`, `fwupd` y `udisks2` en `zp-ldap-01` (Ubuntu 24.04). Se mantuvieron `auditd`, `amazon-ssm-agent` y `snapd` (en Ubuntu el agente de SSM corre como snap). El script se probó primero en `zp-ventas-02` y después en las otras seis.

## 5. Resultados

| Prueba | Resultado | Hora (Guatemala) |
|---|---|---|
| SEG-01 | Entrada por EICE a las siete instancias, antes y después de las ACL y del hardening; con ACL aplicada entraron `zp-visitantes-01` y `zp-ti-01` | 12:38 y 12:49 |
| SEG-02 | `zp-ti-01` → Ventas, NTP y Visitantes: 0 % de pérdida por ICMP; `nmap` con SSH abierto | 12:44:55 |
| SEG-03 | `zp-ventas-01` → `zp-ti-01`: ping 100 % perdido y TCP 22 bloqueado | 12:46:25 |
| SEG-04 | `zp-ntp-01` (Servidores) → `zp-ti-01`: TCP 22 bloqueado | 12:47:09 |
| SEG-05 | `zp-visitantes-01` → Ventas, TI, NTP e Intranet: bloqueado | 12:39 |
| SEG-06 | `zp-visitantes-01` → `https://aws.amazon.com`: `HTTP/2 200` vía NAT | 12:39 |
| HARD-01 | Los únicos puertos en red son TCP 22 y los de cada servicio (UDP 123, TCP 389/636, TCP 80); los cambios del hardening son de configuración, no de puertos | antes y después, 13:03 a 13:21 |
| HARD-02 | `nmap` desde TI: 22 abierto en todos; 80 solo en Intranet; 389 y 636 solo en LDAP; Ventas `filtered` | 12:45 |
| HARD-03 | Las siete instancias con `PermitRootLogin no`, `X11Forwarding no`, `MaxAuthTries 3` y sin contraseña | 13:03 a 13:21 |
| HARD-04 | Ninguna regla de entrada desde `0.0.0.0/0` (comprobado por el script en cada aplicación) | ver sección 6 |

**Defensa en profundidad.** Las pruebas SEG-03, SEG-04 y SEG-05 fallan por el Security Group **y** por la ACL, de modo que el resultado de la prueba por sí solo no aísla una capa. Las dos se documentan y la ACL se muestra en la consola:

| Prueba | Bloqueo en el Security Group | Bloqueo en la Network ACL |
|---|---|---|
| SEG-05 | Ningún SG de destino admite a `zenite-visitantes` como origen | `acl-zenite-visitantes` salida **200** deniega `10.20.0.0/24` |
| SEG-03 y SEG-04 | `zenite-ti` no admite a Ventas ni a Servidores | `acl-zenite-ti` entrada: solo SSH desde el EICE, retorno 1024-65535 y echo reply; el echo request y el SSH desde Ventas no pasan |

## 6. Problemas y correcciones

| Prueba | Error | Corrección |
|---|---|---|
| SEG-01 (1) | `SendSSHPublicKey` denegado para el usuario IAM `Kevin`: ninguna política permitía EICE | La dueña de la cuenta agregó los permisos de EICE y de ACL; SEG-01 (2) correcto |
| HARD-03 (1) | En `zp-ldap-01` el script no desactivó `fwupd` ni `udisks2`: la función que detectaba el servicio fallaba a veces con `grep -q` en una tubería con `pipefail` | `--validar` reveló 2 fallos; se leyó la salida sin tubería y se repitió `aplicar`; HARD-03 (2) sin fallos |
| Despliegue | CloudShell rechazó los scripts (`invalid option name: pipefail`) por los saltos de línea de Windows | `sed -i 's/\r$//'` antes de ejecutarlos |
| Despliegue | El pegado de varios comandos en CloudShell mezcló líneas y no creó nada | Se reemplazó por una función |

HARD-04 se volvió a comprobar con `bash P5_security_groups.sh --validar` al cierre de la sesión: todo en `[OK]` (captura `FASE3_HARD-04_validar_final.png`).

## 7. Limitaciones

- Visitantes → Internet solo funciona con el NAT encendido, y el NAT no está permanente (cuesta ≈ US$1.20 por día). Se encendió de 12:30:26 a 12:53 (hora de Guatemala), unos 23 minutos.
- TI no tiene salida a Internet por ACL: instalar paquetes allí exige quitar o revertir la ACL.
- El egress de los Security Groups está abierto; la restricción interna es de las ACL (y solo en Visitantes y TI).
- Ventas, Servidores, VPN, DMZ e Infra usan la ACL predeterminada; su control es el Security Group.
- La Intranet usa HTTP sin cifrar; no se configuró HTTPS.
- Las ACL no distinguen quién inició una conexión: los puertos efímeros hacia TI pasan la ACL y los frena el Security Group de TI.
- La captura de la ACL en la consola es complementaria; la validación de las reglas de cada ACL la hace `P5_acls.sh --validar`.

## 8. Documentación consultada

- Network ACL: <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html>
- Reglas de ACL (retorno y puertos efímeros): <https://docs.aws.amazon.com/vpc/latest/userguide/nacl-rules.html>
- Security Groups: <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html>
- EC2 Instance Connect Endpoint: <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html>
- `sshd_config`: `man sshd_config` (directivas `Include`, `PermitRootLogin`, `X11Forwarding`, `MaxAuthTries`).

## 9. Filas para la matriz de pruebas (para la Persona 6)

Las filas con su evidencia (los nombres son archivos de `Fase3/evidencias/05_seguridad/`):

| ID | Obtenido | Hora (Guatemala) | Estado | Fig. |
|---|---|---|---|---|
| SEG-01 | Entrada correcta a las siete instancias por EICE; tras aplicar las ACL entran Visitantes y TI. Primer intento fallido por permiso de IAM (ver fallos) | 12:38 y 12:49 | PASS (2) | `FASE3_SEG-01_visitantes_EICE_con_ACL.png`, `FASE3_SEG-01_ti_EICE_con_ACL.png`, `FASE3_SEG-01_intento1_sin_permiso_EICE_cloudshell.png` |
| SEG-02 | `zp-ti-01` → `.10`, `.68`, `.36`: 0 % de pérdida; `nmap` con 22 abierto | 12:44:55 | PASS | `FASE3_SEG-02_HARD-02_ti_ping_nmap_parte1.png` |
| SEG-03 | `zp-ventas-01` → `zp-ti-01`: ping 100 % perdido; TCP 22 bloqueado | 12:46:25 | PASS | `FASE3_SEG-03_ventas_a_ti_bloqueado.png` |
| SEG-04 | `zp-ntp-01` → `zp-ti-01`: TCP 22 bloqueado | 12:47:09 | PASS | `FASE3_SEG-04_servidores_a_ti_bloqueado.png` |
| SEG-05 | `zp-visitantes-01` → `.10`, `.102`, `.68`: 100 % de pérdida; Intranet bloqueada | 12:39 | PASS | `FASE3_SEG-05_06_visitantes_pruebas.png`, `FASE3_SEG-05_NACL_visitantes_salida_consola.png` |
| SEG-06 | `zp-visitantes-01` → `https://aws.amazon.com`: `HTTP/2 200` | 12:39 | PASS | `FASE3_SEG-05_06_visitantes_pruebas.png`, `FASE3_SEG-06_NAT_encendido_ventana.png` |
| HARD-01 | Antes y después en las siete: solo TCP 22 y los puertos propios de cada servicio | 13:03 a 13:21 | PASS | `FASE3_HARD-01_antes_ss_sshd_<instancia>.png`, `FASE3_HARD-03_despues_validar_<instancia>.png` |
| HARD-02 | `nmap` desde `zp-ti-01`: 22 abierto; 80 solo Intranet; 389 y 636 solo LDAP; Ventas `filtered` | 12:45 | PASS | `FASE3_SEG-02_HARD-02_ti_ping_nmap_parte2.png` |
| HARD-03 | Siete instancias con root denegado, X11 desactivado y 3 intentos; sin contraseña | 13:03 a 13:21 | PASS (2) | `FASE3_HARD-03_despues_validar_<instancia>.png` |
| HARD-04 | `P5_security_groups.sh --validar`: ninguna entrada desde `0.0.0.0/0`; `Validacion completa sin fallos.` | cierre de la sesión (ver captura) | PASS | `FASE3_HARD-04_validar_final.png` |

Para la tabla de fallos: SEG-01 (permiso de IAM) y HARD-03 (`fwupd` y `udisks2` en `zp-ldap-01`), como en la sección 6. En el resumen: de las diez pruebas de P5, **ocho aprobadas a la primera, dos corregidas (SEG-01 y HARD-03) y diez aprobadas al final**.
