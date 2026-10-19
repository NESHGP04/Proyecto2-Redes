# Fase 3 – Matriz de pruebas

Formato del Ejercicio 6. Las columnas **Obtenido**, **Hora**, **Estado** y **Fig.** se llenan al ejecutar cada prueba; no se
escribe un resultado que no tenga evidencia. Si una prueba falla, la fila se conserva y la repetición va en otra fila con su
número entre paréntesis (por ejemplo `NTP-02 (2)`); el error y su corrección se anotan en la tabla de fallos.

Responsables: P1 infraestructura · P2 DHCP y NTP · P3 LDAP · P4 Intranet · P5 seguridad.

| ID | Resp. | Servicio | Origen → destino | Esperado | Obtenido | Hora | Estado | Fig. |
|---|---|---|---|---|---|---|---|---|
| INF-01 | P1 | NAT | `zp-ventas-01` → Internet (`curl -I https://aws.amazon.com`) | Responde por el NAT Gateway | | | | |
| INF-02 | P1 | NAT | `zp-ldap-01` → repositorios de paquetes | Instalación de paquetes posible | | | | |
| INF-03 | P1 | NAT | `zp-visitantes-01` → Internet | Responde | | | | |
| INF-04 | P1 | IP pública | Las siete instancias | Sin IPv4 pública | | | | |
| DHCP-01 | P2 | DHCP | Option Set asociado a la VPC | Dominio, DNS y NTP `10.20.0.68` configurados | | | | |
| DHCP-02 | P2 | DHCP | `zp-ventas-01` | Recibe las opciones del Option Set | | | | |
| DHCP-03 | P2 | DHCP | `zp-ti-01` | Recibe las opciones del Option Set | | | | |
| NTP-01 | P2 | NTP | `zp-ntp-01` | `chronyc sources` con fuente válida; sirve a `10.20.0.0/24` | | | | |
| NTP-02 | P2 | NTP | `zp-ventas-01` → `10.20.0.68` | `chronyc tracking` sincronizado con el servidor | | | | |
| NTP-03 | P2 | NTP | `zp-ti-01` → `10.20.0.68` | Sincronizado con el servidor | | | | |
| LDAP-01 | P3 | LDAP | `zp-ldap-01` | `slapd` activo y escuchando en 389 (y 636 si se configura) | | | | |
| LDAP-02 | P3 | LDAP | `zp-ventas-01` → `10.20.0.69` | `ldapsearch` devuelve usuarios y grupos | | | | |
| LDAP-03 | P3 | LDAP | `zp-ti-01` → `10.20.0.69` | `ldapsearch` devuelve usuarios y grupos | | | | |
| LDAP-04 | P3 | LDAP | Usuario de Ventas | `bind` correcto; contraseña errónea rechazada | | | | |
| LDAP-05 | P3 | LDAP | `zp-visitantes-01` → `10.20.0.69` | Bloqueado | | | | |
| WEB-01 | P4 | HTTP | `zp-ventas-01` → `http://10.20.0.71` | HTTP 200 con la página de la Intranet | | | | |
| WEB-02 | P4 | HTTP | `zp-ti-01` → `http://10.20.0.71` | HTTP 200 | | | | |
| WEB-03 | P4 | HTTP | `zp-ldap-01` (Servidores) → `http://10.20.0.71` | HTTP 200 | | | | |
| WEB-04 | P4 | HTTP | `zp-visitantes-01` → `http://10.20.0.71` | Bloqueado (tiempo agotado) | | | | |
| WEB-05 | P4 | HTTP | Desde Internet → Intranet | Inaccesible: sin IP pública y sin regla de entrada | | | | |
| SEG-01 | P5 | SSH | EICE → cada instancia (`ec2-user`) | Conexión correcta | | | | |
| SEG-02 | P5 | ICMP/SSH | `zp-ti-01` → Ventas y Servidores | Permitido | | | | |
| SEG-03 | P5 | ICMP/SSH | `zp-ventas-01` → `zp-ti-01` | Bloqueado | | | | |
| SEG-04 | P5 | ICMP/SSH | Servidores → `zp-ti-01` | Bloqueado | | | | |
| SEG-05 | P5 | ACL | `zp-visitantes-01` → Ventas, TI y Servidores | Bloqueado | | | | |
| SEG-06 | P5 | ACL | `zp-visitantes-01` → Internet | Permitido (vía NAT) | | | | |
| HARD-01 | P5 | Hardening | `ss -tulpn` antes y después, en cada instancia | Solo los puertos necesarios | | | | |
| HARD-02 | P5 | Hardening | `nmap` desde `zp-ti-01` hacia una instancia | Solo los puertos permitidos abiertos | | | | |
| HARD-03 | P5 | SSH | `sshd` de cada instancia | Sin contraseña ni root por SSH | | | | |
| HARD-04 | P5 | Security Groups | Reglas de entrada de los cinco grupos | Ninguna desde `0.0.0.0/0` | | | | |

## Fallos y correcciones

| Prueba | Error encontrado | Acción correctiva | Repetición |
|---|---|---|---|
| | | | |

## Resumen

Pruebas ejecutadas: _ · aprobadas a la primera: _ · corregidas: _ · aprobadas al final: _
