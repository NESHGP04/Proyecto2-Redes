# P5 · Tabla de reglas de seguridad (Fase 3)

**Estado:** borrador para aprobación. No se ha aplicado nada. · Región `us-east-1` · VPC `vpc-zenite-fase2` (`10.20.0.0/24`)

Capas: **Security Group** (con estado, solo permisos, origen por Security Group) y **Network ACL** (sin estado, por número ascendente,
primera coincidencia gana, hay que permitir el retorno). Egress de los Security Groups: **se deja abierto** (decisión del equipo);
la restricción hacia lo interno la hace la ACL.

## 1. Estado inicial (diagnóstico, solo lectura)

| Elemento | Estado encontrado |
|---|---|
| `zenite-servidores` | SSH desde `zenite-eice`; UDP 123 desde `zenite-ventas`, `zenite-ti`, `zenite-servidores` (P2/P5); TCP 389 y 636 desde `zenite-ventas` y `zenite-ti` (P3) |
| `zenite-visitantes` | Solo SSH desde `zenite-eice` |
| `zenite-ventas` | SSH desde `zenite-eice`; ICMP desde `zenite-ventas` y `zenite-ti` |
| `zenite-ti` | SSH desde `zenite-eice`; ICMP desde `zenite-ti` |
| `zenite-eice` | Sin entrada; salida TCP 22 hacia `10.20.0.0/24` |
| Egress (los demás) | `0.0.0.0/0`, todo |
| Entradas desde `0.0.0.0/0` | Ninguna |
| Network ACL | Solo `acl-067acfb0422ab4b7e` (predeterminada), asociada a las 7 subredes, permite todo |
| Rutas | `rt-zenite-infra` → IGW; `rt-zenite-interna` solo local (**sin NAT**); sin IP públicas en instancias |
| Pendiente de diagnóstico | `ss -tulpn` y `sshd -T` por instancia (sin permiso EICE al redactar) |

## 2. Security Groups: reglas de entrada

Las filas **existentes** se conservan. Las **nuevas** son las que aplicará el script del Checkpoint 4.

| ID | Destino (SG) | Origen | Servicio / puerto | Acción | Estado | Justificación |
|---|---|---|---|---|---|---|
| S-01 | todos los SG de instancias | `zenite-eice` | TCP 22 | Permitir | Existente | SSH solo por EICE, sin IP pública (SEG-01) |
| S-02 | `zenite-servidores` | `zenite-ventas`, `zenite-ti`, `zenite-servidores` | UDP 123 | Permitir | Existente | NTP (P2) |
| S-03 | `zenite-servidores` | `zenite-ventas`, `zenite-ti` | TCP 389, 636 | Permitir | Existente | LDAP/LDAPS (P3). Visitantes excluido (LDAP-05) |
| S-04 | `zenite-servidores` | `zenite-ventas`, `zenite-ti`, `zenite-servidores` | **TCP 80** | Permitir | **Nueva** | Intranet (P4); no desde Visitantes ni Internet (WEB-04, WEB-05) |
| S-05 | `zenite-servidores` | `zenite-ti` | **TCP 22** | Permitir | **Nueva** | TI administra todas las subredes |
| S-06 | `zenite-servidores` | `zenite-ti` | **ICMP** | Permitir | **Nueva** | Diagnóstico de TI |
| S-07 | `zenite-ventas` | `zenite-ti` | **TCP 22** | Permitir | **Nueva** | TI → Ventas por SSH (ya tiene ICMP desde TI y Ventas) |
| S-08 | `zenite-visitantes` | `zenite-ti` | **TCP 22, ICMP** | Permitir | **Nueva** | TI → todas las subredes |
| S-09 | `zenite-ti` | (ninguno salvo EICE y TI) | — | Sin cambios | Existente | Nadie inicia hacia TI (ICMP solo de TI, SSH solo de EICE) |
| S-10 | cualquier SG | `0.0.0.0/0` | cualquiera | **Denegar (no existe regla)** | — | Ninguna entrada pública (HARD-04) |

No se abre 443: ningún servicio lo escucha (Fase 1 lo mencionaba para Intranet; se implementó HTTP 80, justificarlo en el reporte).

## 3. Network ACL

Rangos: EICE `10.20.0.144/28` · TI `10.20.0.96/28` · Visitantes `10.20.0.32/27` · VPC `10.20.0.0/24`. Retorno: TCP/UDP `1024-65535`.

### 3.1 `acl-zenite-visitantes` (nueva) → `subnet-zenite-visitantes`

| Dir. | Regla | Origen / destino | Servicio | Acción | Justificación |
|---|---|---|---|---|---|
| Entrada | 100 | `10.20.0.144/28` | TCP 22 | Permitir | SSH por EICE antes de la denegación |
| Entrada | 110 | `10.20.0.96/28` (TI) | TCP 22 | Permitir | TI → Visitantes |
| Entrada | 120 | `10.20.0.96/28` (TI) | ICMP | Permitir | Diagnóstico de TI |
| Entrada | 200 | `10.20.0.0/24` | todo | **Denegar** | Nadie interno inicia hacia Visitantes |
| Entrada | 300 | `0.0.0.0/0` | TCP 1024-65535 | Permitir | Retorno de web desde Internet (vía NAT) |
| Entrada | 310 | `0.0.0.0/0` | UDP 1024-65535 | Permitir | Retorno de DNS |
| Salida | 100 | `10.20.0.144/28` | TCP 1024-65535 | Permitir | Retorno SSH hacia EICE |
| Salida | 110 | `10.20.0.96/28` (TI) | TCP 1024-65535 | Permitir | Retorno SSH hacia TI |
| Salida | 120 | `10.20.0.96/28` (TI) | ICMP | Permitir | Respuesta de ping a TI |
| Salida | 200 | `10.20.0.0/24` | todo | **Denegar** | Visitantes no llega a ninguna subred (SEG-05, WEB-04) |
| Salida | 300 | `0.0.0.0/0` | TCP 80, 443 | Permitir | Web vía NAT |
| Salida | 310 | `0.0.0.0/0` | TCP y UDP 53 | Permitir | DNS externo |
| Ambas | `*` | todo | todo | Denegar | Regla final de AWS |

### 3.2 `acl-zenite-ti` (nueva) → `subnet-zenite-ti`

| Dir. | Regla | Origen / destino | Servicio | Acción | Justificación |
|---|---|---|---|---|---|
| Entrada | 100 | `10.20.0.144/28` | TCP 22 | Permitir | SSH por EICE |
| Entrada | 110 | `10.20.0.0/24` | TCP 1024-65535 | Permitir | **Solo retorno** de conexiones iniciadas por TI |
| Entrada | 120 | `10.20.0.0/24` | UDP 1024-65535 | Permitir | Retorno de NTP/DNS |
| Entrada | 130 | `10.20.0.0/24` | ICMP tipo 0 (echo reply) | Permitir | Retorno de ping de TI; **el echo request queda bloqueado** (Ventas → TI) |
| Salida | 100 | `10.20.0.0/24` | todo | Permitir | TI → todas las subredes |
| Ambas | `*` | todo | todo | Denegar | Sin Internet para TI (ver decisión D1) |

Limitación: la ACL no distingue quién inició una conexión; los puertos efímeros hacia TI pasan la ACL pero **los frena el Security Group de TI** (con estado, sin reglas de entrada de otras subredes). Por eso «nadie inicia hacia TI» se demuestra con el SG, y la ACL refuerza los puertos < 1024.

### 3.3 Resto de subredes
Ventas, Servidores, VPN, DMZ e Infra se quedan en la ACL predeterminada (permite todo); su control es por Security Group (decisión D2).

## 4. Orden de aplicación y rollback

1. **Security Groups** (solo agregan permisos): S-04 a S-08. Probar SEG-01 a SEG-04 y EICE.
2. **ACL Visitantes**: crear y asociar. Comprobar **de inmediato** la entrada por EICE a `zp-visitantes-01` y las pruebas de Visitantes. Si falla: `--revertir`.
3. **ACL TI**: crear y asociar. Comprobar EICE a `zp-ti-01` y TI → resto. Si falla: `--revertir`.
4. Cada paso, un cambio a la vez, con la entrada por EICE verificada después.

`--revertir` asocia las subredes de nuevo a la ACL predeterminada (buscada por `IsDefault`) y elimina las dos ACL nuevas. Los SG nuevos solo agregan permisos y se retiran con `revoke`.

## 5. Pruebas (IDs de `Fase3/reporte/matriz-de-pruebas.md`)

| ID | Qué demuestra | Esperado | Reglas que lo sostienen |
|---|---|---|---|
| SEG-01 | SSH por EICE a cada instancia (`ec2-user`; `ubuntu` en `zp-ldap-01`) | Conexión correcta | S-01; ACL: entrada 100 (EICE) |
| SEG-02 | `zp-ti-01` → Ventas y Servidores (ICMP/SSH) | Permitido | S-05, S-06, S-07; ACL TI salida 100 |
| SEG-03 | `zp-ventas-01` → `zp-ti-01` | Bloqueado | S-09; ACL TI entrada (echo request y puertos < 1024 no pasan) |
| SEG-04 | Servidores → `zp-ti-01` | Bloqueado | S-09; ACL TI entrada |
| SEG-05 | `zp-visitantes-01` → Ventas, TI y Servidores | Bloqueado (tiempo agotado) | ACL Visitantes salida 200 |
| SEG-06 | `zp-visitantes-01` → Internet | Permitido vía NAT (requiere NAT encendido) | ACL Visitantes salida 300-310 y retorno 300-310 |
| HARD-01 | `ss -tulpn` antes y después, por instancia | Solo los puertos necesarios | Diagnóstico y hardening |
| HARD-02 | `nmap` desde `zp-ti-01` hacia una instancia | Solo los puertos permitidos abiertos | Requiere instalar `nmap` en `zp-ti-01` antes de su ACL (D1) |
| HARD-03 | `sshd` de cada instancia | Sin contraseña ni root por SSH | Revisión de `sshd -T` |
| HARD-04 | Reglas de entrada de los cinco grupos | Ninguna desde `0.0.0.0/0` | S-10 |

WEB-01 a WEB-05 (P4) y LDAP-05 (P3) dependen de las mismas reglas.

## 6. Decisiones pendientes de aprobación

| ID | Decisión | Recomendación |
|---|---|---|
| D1 | TI sin salida a Internet por ACL | Sí. Instalar `nmap` en `zp-ti-01` **antes** de aplicar su ACL (con NAT encendido) |
| D2 | Sin ACL propia para Ventas ni Servidores | Sí: SG ya filtra; menos riesgo de cortar EICE |
| D3 | No abrir 443 | Sí: nada lo escucha |
| D4 | Permitir TI → Visitantes (SSH e ICMP) | Sí: «TI conecta a todas las subredes» |
| D5 | Egress de SG abierto | Sí (ya acordado) |

## 7. Por verificar
- El tráfico a Amazon DNS, DHCP, metadata y Amazon Time Sync no lo filtran las ACL (documentación de AWS); se comprobará con las pruebas de Visitantes.
- Puertos reales abiertos por instancia (`ss -tulpn`) y estado de `sshd`: pendiente del permiso EICE.

## 8. Documentación consultada
- Network ACL: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- Reglas de ACL (retorno y puertos efímeros): https://docs.aws.amazon.com/vpc/latest/userguide/nacl-rules.html
- Security Groups: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- Instance Connect Endpoint: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html
