# Fase 3 – Matriz de pruebas

Formato del Ejercicio 6. Las columnas **Obtenido**, **Hora**, **Estado** y **Fig.** se llenan al ejecutar cada prueba; no se
escribe un resultado que no tenga evidencia. Si una prueba falla, la fila se conserva y la repetición va en otra fila con su
número entre paréntesis (por ejemplo `NTP-02 (2)`); el error y su corrección se anotan en la tabla de fallos.

Responsables: P1 infraestructura · P2 DHCP y NTP · P3 LDAP · P4 Intranet · P5 seguridad.

| ID | Resp. | Servicio | Origen → destino | Esperado | Obtenido | Hora | Estado | Fig. |
|---|---|---|---|---|---|---|---|---|
| INF-01 | P1 | NAT | `zp-ventas-01` → Internet (`curl -I https://aws.amazon.com`) | Responde por el NAT Gateway | `HTTP/2 200`; salida confirmada por Elastic IP `3.95.121.55` | 22:24 UTC | PASS | INF-01 |
| INF-02 | P1 | NAT | `zp-ldap-01` → repositorios de paquetes | Instalación de paquetes posible | `apt-get update`: descargó 33.6 MB en 5 s | 22:25 UTC | PASS | INF-02 |
| INF-03 | P1 | NAT | `zp-visitantes-01` → Internet | Responde | `HTTP/2 200`; salida confirmada por Elastic IP `3.95.121.55` | 22:23 UTC | PASS | INF-03 |
| INF-04 | P1 | IP pública | Las siete instancias | Sin IPv4 pública | Ninguna instancia tiene IPv4 pública asignada (verificado en consola y script) | 22:06 UTC | PASS | INF-04 |
| DHCP-01 | P2 | DHCP | Option Set asociado a la VPC | Dominio, DNS y NTP `10.20.0.68` configurados | `dopt-zenite-fase3`: `zenite.internal`, `AmazonProvidedDNS` y `10.20.0.68` activo en VPC | 16:55 UTC | PASS | DHCP-01 |
| DHCP-02 | P2 | DHCP | `zp-ventas-01` | Recibe las opciones del Option Set | `networkctl`: NTP `10.20.0.68`, DNS `10.20.0.2`, dominio `zenite.internal`. Lease confirmado | 17:05 UTC | PASS | DHCP-02 |
| DHCP-03 | P2 | DHCP | `zp-ti-01` | Recibe las opciones del Option Set | `networkctl`: NTP `10.20.0.68`, DNS `10.20.0.2`, dominio `zenite.internal` | 17:18 UTC | PASS | DHCP-03 |
| NTP-01 | P2 | NTP | `zp-ntp-01` | `chronyc sources` con fuente válida; sirve a `10.20.0.0/24` | `^*` en `169.254.169.123` (stratum 3); chronyd en UDP 123; atiende a clientes `.10` y `.102` | 17:28 UTC | PASS | NTP-01 |
| NTP-02 | P2 | NTP | `zp-ventas-01` → `10.20.0.68` | `chronyc tracking` sincronizado con el servidor | `^*` en `10.20.0.68` (stratum 5, Leap status Normal, offset 3.9 µs) | 22:51 UTC | PASS | NTP-02 |
| NTP-03 | P2 | NTP | `zp-ti-01` → `10.20.0.68` | Sincronizado con el servidor | `^*` en `10.20.0.68` (Reach 377, stratum 5, Leap status Normal, offset 2.5 µs) | 23:00 UTC | PASS | NTP-03 |
| LDAP-01 | P3 | LDAP | `zp-ldap-01` | `slapd` activo y escuchando en 389 (y 636 si se configura) | `systemctl active`; `ss -tlnp`: 389 y 636; `P3_ldap.sh --validar`: 8 `[OK]` | 00:10 UTC | PASS | LDAP-01 |
| LDAP-02 (1) | P3 | LDAP | `zp-ventas-01` → `10.20.0.69` | `ldapsearch` devuelve usuarios y grupos | `ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)` | 00:13 UTC | FAIL | – |
| LDAP-02 (2) | P3 | LDAP | `zp-ventas-01` → `10.20.0.69` | `ldapsearch` devuelve usuarios y grupos | Por 389: grupos `ventas`/`ti` y 4 usuarios; por LDAPS (636): los 2 grupos | 00:15 UTC | PASS | LDAP-02 |
| LDAP-03 | P3 | LDAP | `zp-ti-01` → `10.20.0.69` | `ldapsearch` devuelve usuarios y grupos | Las mismas 6 entradas por 389 y los 2 grupos por `ldaps://` | 00:15 UTC | PASS | LDAP-03 |
| LDAP-04 | P3 | LDAP | Usuario de Ventas | `bind` correcto; contraseña errónea rechazada | Contraseña válida: `dn:uid=ventas01,...` (exit 0); errónea: `Invalid credentials (49)` | 00:16 UTC | PASS | LDAP-04 |
| LDAP-05 | P3 | LDAP | `zp-visitantes-01` → `10.20.0.69` | Bloqueado | `Can't contact LDAP server (-1)` con timeout 5s; tiempo agotado (exit 124) | 00:16 UTC | PASS | LDAP-05 |
| WEB-01 | P4 | HTTP | `zp-ventas-01` → `http://10.20.0.71` | HTTP 200 con la página de la Intranet | `HTTP/1.1 200 OK` (8,456 bytes, UTF-8); habilitado por regla S-04 de SG | 07:26 UTC / 12:45 GT | PASS | FASE3_WEB-LOCAL_Intranet_HTTP200.png |
| WEB-02 | P4 | HTTP | `zp-ti-01` → `http://10.20.0.71` | HTTP 200 | `HTTP/1.1 200 OK`; certificado por escaneo `nmap` desde TI (`80/tcp open http`) | 12:45 GT | PASS | FASE3_SEG-02_HARD-02_ti_ping_nmap_parte2.png |
| WEB-03 | P4 | HTTP | `zp-ldap-01` (Servidores) → `http://10.20.0.71` | HTTP 200 | `HTTP/1.1 200 OK`; comunicación inter-servidores autorizada en Nginx y SG | 07:26 UTC / 12:45 GT | PASS | FASE3_WEB-LOCAL_Intranet_HTTP200.png |
| WEB-04 | P4 | HTTP | `zp-visitantes-01` → `http://10.20.0.71` | Bloqueado (tiempo agotado) | Bloqueado: tiempo agotado (`Connection timed out`); regla 200 de ACL y SG | 12:39 GT | PASS | FASE3_SEG-05_06_visitantes_pruebas.png |
| WEB-05 | P4 | HTTP | Desde Internet → Intranet | Inaccesible: sin IP pública y sin regla de entrada | Inaccesible: 0 IPs públicas asignadas y 0 reglas públicas en SG | 22:06 UTC / 13:25 GT | PASS | FASE3_INF-04_Instancias_Sin_IP_Publica.png |
| SEG-01 (1) | P5 | SSH | EICE → cada instancia (`ec2-user`) | Conexión correcta | `SendSSHPublicKey` denegado (usuario IAM `Kevin` sin permisos EICE) | 12:38 GT | FAIL | SEG-01 (intento 1) |
| SEG-01 (2) | P5 | SSH | EICE → cada instancia (`ec2-user`) | Conexión correcta | Entrada correcta a las 7 instancias por EICE con ACL aplicada | 12:49 GT | PASS | FASE3_SEG-01_visitantes_EICE_con_ACL.png |
| SEG-02 | P5 | ICMP/SSH | `zp-ti-01` → Ventas y Servidores | Permitido | `zp-ti-01` → `.10`, `.68`, `.36`: 0 % de pérdida ICMP; `nmap` con 22 abierto | 12:44 GT | PASS | FASE3_SEG-02_HARD-02_ti_ping_nmap_parte1.png |
| SEG-03 | P5 | ICMP/SSH | `zp-ventas-01` → `zp-ti-01` | Bloqueado | `zp-ventas-01` → `zp-ti-01`: ping 100 % perdido; TCP 22 bloqueado por SG y ACL | 12:46 GT | PASS | FASE3_SEG-03_ventas_a_ti_bloqueado.png |
| SEG-04 | P5 | ICMP/SSH | Servidores → `zp-ti-01` | Bloqueado | `zp-ntp-01` → `zp-ti-01`: TCP 22 bloqueado por SG y ACL | 12:47 GT | PASS | FASE3_SEG-04_servidores_a_ti_bloqueado.png |
| SEG-05 | P5 | ACL | `zp-visitantes-01` → Ventas, TI y Servidores | Bloqueado | `zp-visitantes-01` → `.10`, `.102`, `.68`: 100 % pérdida; Intranet bloqueada | 12:39 GT | PASS | FASE3_SEG-05_06_visitantes_pruebas.png |
| SEG-06 | P5 | ACL | `zp-visitantes-01` → Internet | Permitido (vía NAT) | `zp-visitantes-01` → `https://aws.amazon.com`: `HTTP/2 200` vía NAT | 12:39 GT | PASS | FASE3_SEG-05_06_visitantes_pruebas.png |
| HARD-01 | P5 | Hardening | `ss -tulpn` antes y después, en cada instancia | Solo los puertos necesarios | Antes y después en las 7: solo TCP 22 y puertos propios de servicio | 13:03 GT | PASS | FASE3_HARD-01_antes_ss_sshd_zp-ventas-01.png |
| HARD-02 | P5 | Hardening | `nmap` desde `zp-ti-01` hacia una instancia | Solo los puertos permitidos abiertos | `nmap`: 22 abierto; 80 solo Intranet; 389/636 solo LDAP; Ventas `filtered` | 12:45 GT | PASS | FASE3_SEG-02_HARD-02_ti_ping_nmap_parte2.png |
| HARD-03 (1) | P5 | SSH | `sshd` de cada instancia | Sin contraseña ni root por SSH | En `zp-ldap-01` falló desactivación de `fwupd` y `udisks2` por error en script | 13:10 GT | FAIL | FASE3_HARD-03_aplicar_zp-ldap-01_incompleto.png |
| HARD-03 (2) | P5 | SSH | `sshd` de cada instancia | Sin contraseña ni root por SSH | 7 instancias con `PermitRootLogin no`, `X11Forwarding no`, 3 intentos; sin contraseña | 13:21 GT | PASS | FASE3_HARD-03_despues_validar_zp-ventas-01.png |
| HARD-04 | P5 | Security Groups | Reglas de entrada de los cinco grupos | Ninguna desde `0.0.0.0/0` | `P5_security_groups.sh --validar`: 0 reglas desde `0.0.0.0/0`; validación sin fallos | 13:25 GT | PASS | FASE3_HARD-04_validar_final.png |

## Fallos y correcciones

| Prueba | Error encontrado | Acción correctiva | Repetición |
|---|---|---|---|
| LDAP-02 (1) | `Can't contact LDAP server (-1)`: `zenite-servidores` solo permitía SSH (22) y NTP (UDP 123); no tenía reglas para 389 ni 636 | Se autorizaron reglas de entrada TCP 389 y 636 en `zenite-servidores` desde `zenite-ventas` y `zenite-ti` | LDAP-02 (2): PASS |
| SEG-01 (1) | `SendSSHPublicKey` denegado para el usuario IAM `Kevin`: sin políticas para EICE ni Network ACL | La administradora de la cuenta agregó los permisos IAM de EICE y ACL | SEG-01 (2): PASS |
| HARD-03 (1) | En `zp-ldap-01` no se desactivaron `fwupd` ni `udisks2` por fallo de `grep -q` con `pipefail` | Se corrigió la función en `P5_hardening.sh` leyendo la salida sin tubería y se repitió `aplicar` | HARD-03 (2): PASS |

## Resumen

Pruebas ejecutadas: 28 (31 con repeticiones) · aprobadas a la primera: 25 · corregidas: 3 (LDAP-02, SEG-01, HARD-03) · aprobadas al final: 28 (100 % de la matriz completada y aprobada)


