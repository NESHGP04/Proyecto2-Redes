# LDAP (Persona 3): instalación y pruebas

Servidor OpenLDAP (`slapd`) en `zp-ldap-01` (`10.20.0.69`, Ubuntu 24.04, subred Servidores). Base `dc=zenite,dc=internal`
(mismo dominio que el DHCP Option Set), administrador `cn=admin,dc=zenite,dc=internal`. Puertos: 389 (`ldap://`) y 636
(`ldaps://`, certificado autofirmado con SAN `IP:10.20.0.69`).

| Archivo | Contenido |
|---|---|
| `P3_ldap.sh` | `instalar` (pide `si`) y `--validar` (solo lectura). Se ejecuta dentro de `zp-ldap-01`. |
| `zenite.ldif` | `ou=People`, `ou=Groups`, grupos `ventas` (gid 10001) y `ti` (gid 10002), usuarios `ventas01`, `ventas02`, `ti01`, `ti02`. Sin contraseñas: `@@HASH_USUARIOS@@` se reemplaza al instalar. |
| `tls.ldif` | Certificado y llave en `cn=config`. |
| `zenite-ldap.crt` | Certificado público del servidor (se copia a los clientes para `ldaps://`). La llave no sale de `zp-ldap-01`. |

## Contraseñas

Solo de laboratorio, en el `.env` local (ignorado por git): `LDAP_ADMIN_PASSWORD` (administrador) y `LDAP_USER_PASSWORD`
(los cuatro usuarios de prueba). Si no están en el entorno, `P3_ldap.sh` las pide sin eco. No se escriben en archivos
versionados ni en capturas: en las pruebas se usa `-W`, que las pide sin mostrarlas.

## Instalación (en `zp-ldap-01`, usuario `ubuntu`, con el NAT encendido)

```bash
mkdir -p /tmp/p3-ldap && cd /tmp/p3-ldap      # copiar aquí P3_ldap.sh, zenite.ldif y tls.ldif
sudo bash P3_ldap.sh instalar                  # escribe si y las dos contraseñas
bash P3_ldap.sh --validar                      # debe terminar en "RESULTADO: todo correcto."
```

Es idempotente: si `slapd` ya está instalado con `dc=zenite,dc=internal`, no lo reinstala; el certificado no se regenera;
las entradas que ya existen no se modifican (para cambiar la contraseña de un usuario se usa `ldappasswd`).

## Clientes (`zp-ventas-01`, `zp-ti-01`, `zp-visitantes-01`, Amazon Linux 2023, con el NAT encendido)

```bash
sudo dnf install -y openldap-clients
# copiar zenite-ldap.crt a ~/zenite-ldap.crt
```

## Pruebas (matriz LDAP-01 a LDAP-05)

Requieren en `zenite-servidores` la entrada TCP 389 y 636 desde `zenite-ventas` y `zenite-ti` (Persona 5), y ninguna desde
`zenite-visitantes`.

```bash
# LDAP-01 (zp-ldap-01)
bash P3_ldap.sh --validar
sudo ss -tlnp | grep slapd

# LDAP-02 (zp-ventas-01) y LDAP-03 (zp-ti-01)
ldapsearch -x -LLL -H ldap://10.20.0.69 -b dc=zenite,dc=internal \
  "(|(objectClass=posixAccount)(objectClass=posixGroup))" uid cn gidNumber memberUid

# LDAP-04 (zp-ventas-01): bind correcto y bind con contraseña errónea
LDAPTLS_CACERT=~/zenite-ldap.crt ldapwhoami -x -H ldaps://10.20.0.69 \
  -D uid=ventas01,ou=People,dc=zenite,dc=internal -W     # contraseña correcta: dn:uid=ventas01,...
LDAPTLS_CACERT=~/zenite-ldap.crt ldapwhoami -x -H ldaps://10.20.0.69 \
  -D uid=ventas01,ou=People,dc=zenite,dc=internal -W     # contraseña errónea: Invalid credentials (49)

# LDAP-05 (zp-visitantes-01): debe agotar el tiempo
ldapsearch -x -o nettimeout=5 -H ldap://10.20.0.69 -b dc=zenite,dc=internal "(uid=*)" uid
```
