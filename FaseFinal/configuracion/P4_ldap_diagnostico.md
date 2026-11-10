# P4 · Checkpoint 2: diagnóstico de LDAP desde el navegador

Estado: preparación local; no se ha consultado AWS ni probado LDAP en esta sesión.
Fecha de preparación: 9 de noviembre de 2026, Guatemala. La recolección imprime su hora real en UTC.

## 1. Qué comprobar y en qué orden

1. Instancias existentes y salud EC2: `zp-ldap-01`, `zp-ventas-01`, `zp-ti-01`.
2. Servicio `slapd` y escucha 389/636 dentro de `zp-ldap-01`.
3. Grupos efectivos, ACL y sus retornos. P3 administra cualquier cambio de firewall.
4. Nombre usado por el cliente, SAN y certificado de confianza.
5. Hora, sincronización y diferencias respecto de las pruebas históricas.

Se reutilizan las instancias existentes. Visitantes se consulta en el inventario; su encendido se coordinará para LDAP-05 en el checkpoint 3.
Para estas consultas no se necesita NAT ni instalar paquetes. Si falta una herramienta, conservar la salida; la instalación se decide después.

## 2. Primera recolección: AWS CloudShell

1. Entra a la consola de AWS con tu usuario IAM y selecciona **N. Virginia (`us-east-1`)**.
2. Abre **CloudShell**, el icono de terminal de la consola. El prompt de CloudShell suele ser `~ $`.
3. En **Actions → Upload file**, sube únicamente `FaseFinal/configuracion/P4_ldap_diagnostico.sh`.
   Si el navegador está en Windows y el repositorio en WSL, en el Explorador abre **Linux → tu distribución → home → cisco** y sigue la ruta del repositorio.
   No se necesita instalar AWS CLI en WSL ni copiar un `.env` a CloudShell.
4. Ejecuta este comando en CloudShell. Solo consulta AWS y guarda un registro en el directorio personal de CloudShell:

   ```bash
   bash "$HOME/P4_ldap_diagnostico.sh" --validar
   ```

5. Copia la salida y compártela para interpretarla. El script muestra la ruta exacta del TXT; si la terminal recorta la salida, consúltalo con `cat` usando esa ruta.
6. Si aparece `stopped`, un problema de salud, duplicados, un conflicto de IP o `AccessDenied`, conserva el error y detente antes de entrar a las instancias.
   P1 debe coordinar el encendido de las tres instancias y confirmar 3/3. Encenderlas cambia AWS: se mostrará el comando y se solicitará confirmación antes de hacerlo.

Código de salida 1 puede indicar instancias detenidas o datos de salud pendientes; no prueba que `slapd` esté averiado.
Si falta EBS en la respuesta de la API, verificar la consola; no inventar el tercer control.
Un permiso insuficiente de AWS tampoco demuestra bloqueo de red hacia LDAP.

Si aparece `invalid option name: pipefail`, se puede corregir únicamente la copia del script subida a CloudShell:

```bash
sed -i 's/\r$//' "$HOME/P4_ldap_diagnostico.sh"
```

Ese comando cambia los saltos de línea del archivo local; no configura AWS ni una instancia.

## 3. Servicio: dentro de `zp-ldap-01`

Después de comprobar que está encendida y saludable:

1. Abre **EC2 → Instances** y selecciona por nombre `zp-ldap-01`.
2. Pulsa **Connect → EC2 Instance Connect → Connect using EC2 Instance Connect Endpoint**.
3. Selecciona el endpoint cuyo ID acaba de consultar el script y usa el usuario **`ubuntu`**.
4. Pulsa **Connect**. En la nueva terminal ejecuta cada bloque por separado, esperando el prompt.

Confirma identidad, IP y hora. Esperado: `zp-ldap-01` y `10.20.0.69`:

```bash
uname -n
ip -4 -o addr show
date -u
```

Si el hostname o la IP no coinciden, detente. Estos comandos solo consultan el servicio y los puertos; `sudo -n` no pide contraseña:

```bash
systemctl status slapd --no-pager --full --lines=0
```

```bash
sudo -n ss -ltnp '( sport = :389 or sport = :636 )'
```

Esperado: `active (running)` y `slapd` escuchando en ambos puertos. Si `sudo` es denegado, registra el error; no indica que falten los puertos.

Revisa únicamente los nombres de archivos TLS, los servicios y el certificado **público**:

```bash
awk '/^[[:space:]]*SLAPD_SERVICES=/' /etc/default/slapd
```

Consulta solo las rutas TLS de `cn=config`; no muestra el contenido de las llaves:

```bash
timeout --kill-after=2s 10s sudo -n ldapsearch -Q -Y EXTERNAL -H ldapi:/// -LLL -b cn=config -s base '(objectClass=*)' olcTLSCACertificateFile olcTLSCertificateFile olcTLSCertificateKeyFile
```

Si las rutas de los certificados difieren de `/etc/ldap/zenite-ldap.crt`, registra la diferencia antes de asumir que ese archivo es el certificado utilizado.

```bash
openssl x509 -in /etc/ldap/zenite-ldap.crt -noout -subject -issuer -dates -ext subjectAltName -fingerprint -sha256
```

```bash
openssl verify -CAfile /etc/ldap/zenite-ldap.crt -verify_ip 10.20.0.69 /etc/ldap/zenite-ldap.crt
```

No leer la llave privada, el `.env`, `slapcat` completo ni los atributos `userPassword`.

Consulta local anónima, con tiempos límite. Solo lee el DN raíz:

```bash
timeout --kill-after=2s 10s ldapsearch -x -LLL -o nettimeout=5 -l 5 -H ldap://127.0.0.1 -b dc=zenite,dc=internal -s base '(objectClass=*)' dn
```

Consulta el reloj sin cambiarlo:

```bash
timedatectl status
```

```bash
chronyc tracking
```

Si falta `chronyc`, registra que no está instalado; `date -u` sigue permitiendo comparar la hora.
No se cambia la fuente NTP durante el diagnóstico.

## 4. Red, confianza y consulta: Ventas y TI

Después de revisar el servicio y la sección de grupos/ACL de la salida de CloudShell, conecta desde EC2 de la misma manera a:

| Instancia | Usuario de conexión | IP esperada |
|---|---|---|
| `zp-ventas-01` | `ec2-user` | `10.20.0.10` |
| `zp-ti-01` | `ec2-user` | `10.20.0.102` |

Ejecuta los mismos bloques dentro de **cada cliente**. Son consultas anónimas; no necesitan contraseñas:

```bash
uname -n
ip -4 -o addr show
date -u
command -v ldapsearch
```

Conserva el resultado de cada conexión TCP. Código 0 indica conexión establecida; 124 indica que `timeout` agotó el tiempo; otros códigos requieren leer el error:

```bash
timeout --kill-after=2s 5s bash -c 'exec 3<>/dev/tcp/10.20.0.69/389'; printf 'TCP389 exit=%s\n' "$?"
```

```bash
timeout --kill-after=2s 5s bash -c 'exec 3<>/dev/tcp/10.20.0.69/636'; printf 'TCP636 exit=%s\n' "$?"
```

Consulta anónima por 389; sirve para separar conectividad LDAP y TLS, sin enviar contraseñas:

```bash
timeout --kill-after=2s 10s ldapsearch -x -LLL -o nettimeout=5 -l 5 -H ldap://10.20.0.69 -b dc=zenite,dc=internal -s base '(objectClass=*)' dn
```

Comprueba la confianza configurada sin mostrar otros archivos sensibles:

```bash
printf 'LDAPTLS_CACERT=%s\nLDAPTLS_REQCERT=%s\n' "${LDAPTLS_CACERT:-no definida}" "${LDAPTLS_REQCERT:-no definida}"
ls -l "$HOME/zenite-ldap.crt"
```

```bash
for p4_conf in /etc/openldap/ldap.conf /etc/ldap/ldap.conf; do if [ -r "$p4_conf" ]; then printf '%s\n' "$p4_conf"; awk '/^[[:space:]]*(TLS_CACERT|TLS_CACERTDIR|TLS_REQCERT|URI|BASE)[[:space:]]/' "$p4_conf"; fi; done
```

Consulta primero con la configuración actual del cliente, forzando verificación TLS:

```bash
timeout --kill-after=2s 10s env LDAPTLS_REQCERT=demand ldapsearch -x -LLL -o nettimeout=5 -l 5 -H ldaps://10.20.0.69 -b dc=zenite,dc=internal -s base '(objectClass=*)' dn
```

Si el archivo público existe, consulta sus SAN, vigencia y huella; compara la huella con la del servidor:

```bash
openssl x509 -in "$HOME/zenite-ldap.crt" -noout -subject -dates -ext subjectAltName -fingerprint -sha256
```

Comprueba el certificado que presenta realmente el servicio por 636. Este comando falla ante un error de verificación; no acepta certificados sin validar:

```bash
timeout --kill-after=2s 10s openssl s_client -connect 10.20.0.69:636 -CAfile "$HOME/zenite-ldap.crt" -verify_ip 10.20.0.69 -verify_return_error -brief < /dev/null
```

Ahora indica explícitamente ese certificado de confianza. Esta variable se aplica solo a este comando; no instala ni reemplaza certificados:

```bash
timeout --kill-after=2s 10s env LDAPTLS_REQCERT=demand LDAPTLS_CACERT="$HOME/zenite-ldap.crt" ldapsearch -x -LLL -o nettimeout=5 -l 5 -H ldaps://10.20.0.69 -b dc=zenite,dc=internal '(objectClass=posixGroup)' cn memberUid
```

Para resolver el nombre interno y revisar la hora:

```bash
getent ahostsv4 zp-ldap-01.zenite.internal
chronyc tracking
```

La ausencia de resolución no explica un fallo cuando el comando usa la IP. Que el certificado incluya un DNS SAN tampoco crea un registro DNS.
Si las consultas anónimas están denegadas, conservar el código y error: no asumir que la red o el certificado fallan.
El bind válido/incorrecto y las repeticiones R1/R2 pertenecen al checkpoint 3.

## 5. Hipótesis provisionales, en orden de prioridad

El orden es orientativo y cambiará según las salidas. Ninguna es todavía la causa confirmada de la demo.

| Prioridad | Hipótesis y antecedente | Prueba que la distingue |
|---|---|---|
| 1 | Instancia detenida o arranque incompleto. P3 documentó el apagado al cerrar su sesión. | Inventario actual y controles EC2; comprobar disponibilidad de las tres instancias. |
| 2 | Cliente sin confianza explícita o con copia distinta del certificado. La evidencia histórica LDAP-04 registra fallo sin `LDAPTLS_CACERT`. | Comparar TCP, consulta por 389, LDAPS con configuración actual, LDAPS con CA explícita y huellas servidor/cliente. |
| 3 | Regresión de SG/ACL, incluido el retorno de TI. Hubo un fallo histórico por reglas LDAP faltantes; su corrección está documentada. | Revisar grupos realmente asociados, 389/636 desde Ventas/TI y ACL efectivas; contrastar con los dos clientes. Un timeout solo no identifica la capa. |
| 4 | `slapd` inactivo o sin listener 636. | Estado del servicio, `SLAPD_SERVICES`, `ss` y consulta local. |
| 5 | Nombre interno sin DNS o nombre/IP fuera del SAN del certificado actualmente servido. | Comando exacto de la demo, `getent`, SAN y comparación del certificado real. El certificado versionado sí incluye `10.20.0.69`. |
| 6 | Reloj fuera del período de validez o certificado servido distinto/vencido. | Hora UTC, estado del reloj, `chronyc`, fechas del certificado y resultado TLS. |

Si todo funciona ahora y no existe salida del fallo histórico, documentar «causa histórica no determinable con la evidencia disponible». No atribuirla retrospectivamente a una hipótesis.

## 6. Evidencias y coordinación

Son diagnósticos, no resultados aprobados de LDAP-01..05:

- `FINAL_LDAP-DIAG_nube.txt`: salida del script con hora real. Captura equivalente `.png` con N. Virginia visible.
- `FINAL_LDAP-DIAG_servidor.txt` y `.png`: hostname, hora, servicio, puertos y certificado público.
- `FINAL_LDAP-DIAG_ventas.txt` y `.png`: hostname, hora, comandos y salidas TCP/LDAP/TLS.
- `FINAL_LDAP-DIAG_ti.txt` y `.png`: las mismas consultas desde TI.

Guardar las evidencias reales en `FaseFinal/evidencias/04_snmp_ldap/`. Si se transcriben salidas del chat, indicar que son transcripciones.
No se han creado estos archivos de evidencia ni se han asignado resultados.

P1 coordina encendido y cierre; P3 recibe las solicitudes de red si el diagnóstico confirma un problema; P5 recibirá después las filas con resultados.
Al terminar, coordinar con P1 la detención de las instancias que se hayan encendido para esta sesión. Cerrar el navegador no detiene EC2.
No se debe crear NAT para esta recolección. El checkpoint 2 se cierra al interpretar las salidas; la corrección requiere aprobación del checkpoint 3.

## 7. Fuentes verificadas para este diagnóstico

Consultadas el 9 de noviembre de 2026. Se verificaron comandos y opciones en estas fuentes; no certifican el estado de AWS del equipo.

- AWS CLI, inventario: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-instances.html
- AWS CLI, salud y `AttachedEbsStatus`: https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-instance-status.html
- AWS, conexión por EICE: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html
- Ubuntu, LDAP y TLS: https://ubuntu.com/server/docs/how-to/openldap/ldap-and-tls/
- Ubuntu, manual `ldapsearch`: https://manpages.ubuntu.com/manpages/noble/en/man1/ldapsearch.1.html
- Ubuntu, manual `ldap.conf`: https://manpages.ubuntu.com/manpages/noble/en/man5/ldap.conf.5.html
- OpenSSL, verificación de certificados e IP: https://docs.openssl.org/3.0/man1/openssl-verification-options/
- OpenSSL, cliente TLS y `-verify_return_error`: https://docs.openssl.org/3.0/man1/openssl-s_client/

Los enlaces de manual de OpenLDAP no pudieron abrirse con la herramienta de consulta; se contrastaron las opciones con los manuales publicados por Ubuntu.

## 8. Verificación local del recolector

`bash -n` correcto. Se ejecutaron 11 escenarios locales con una CLI simulada que rechaza cualquier operación fuera de la lista de `describe-*`:
inventario saludable, todas detenidas, solo Visitantes detenida, instancia duplicada, VPC duplicada, IP fuera del plan, IPv4 pública inesperada,
etiqueta de proyecto ajena, control EBS ausente, consulta denegada y modo de escritura rechazado. Se comprobaron los códigos de salida y el registro.
Las simulaciones no contactaron AWS y no son evidencia de LDAP funcionando.

## 9. Cierre del checkpoint 2 para revisión humana

Resultados recibidos el 9-nov-2026 de Guatemala. Se conservaron las transcripciones en `FaseFinal/evidencias/04_snmp_ldap/` (ruta desde este documento: `../evidencias/04_snmp_ldap/`).

| Comprobación | Resultado real y alcance | Evidencia |
|---|---|---|
| Inventario inicial | LDAP, Ventas y TI detenidas; después el humano las encendió. No determina la causa de la demo anterior. | `FINAL_LDAP-DIAG_nube_20261110T005734Z.txt`, `FINAL_LDAP-DIAG_encendido.txt` |
| Servicio | `slapd` activo, escucha 389/636; conexión EICE al servidor conseguida. | `FINAL_LDAP-DIAG_servidor_servicio.txt` |
| Certificado del servidor | SAN correcto, `openssl verify` devuelve `OK`; consulta local por LDAPS devuelve dos grupos. | `FINAL_LDAP-DIAG_servidor_tls.txt` |
| Cliente TI | 9-nov, 19:27:54 Guatemala (`date`); falla la consulta con confianza actual, funciona con CA explícita. | `FINAL_LDAP-DIAG_ti.txt` |
| Cliente Ventas | 9-nov, 19:34:22 Guatemala (`date`); mismo resultado que TI. | `FINAL_LDAP-DIAG_ventas.txt` |
| Confianza | Los certificados de ambos clientes coinciden en huella con el servidor y el repositorio. El cambio de `LDAPTLS_CACERT` permite las consultas manteniendo `LDAPTLS_REQCERT=demand`. | Certificados y consultas anteriores |
| Controles EC2, NTP y bind | Controles 3/3 no recibidos; no se ha acreditado sincronización NTP ni probado bind válido/incorrecto en esta etapa. | Pendiente |

Conclusión: las consultas actuales funcionan desde Ventas y TI con confianza explícita. Se reprodujo el fallo con la configuración actual de confianza de ambos clientes, pero no se inspeccionaron todos sus valores predeterminados. No hay evidencia de un bloqueo de red que impida las consultas exitosas.

La omisión de la CA explícita es la hipótesis prioritaria para la falla de la demo pasada; su causa exacta sigue sin confirmar porque no se conserva el comando/error. No presentar esta hipótesis como causa histórica comprobada.

Decisión propuesta para el checkpoint 3:

- **A, recomendada:** incluir la CA explícita y verificación obligatoria en el guion, con comprobaciones previas y tiempos límite. Reutiliza los certificados existentes.
- **B:** instalar/configurar confianza persistente en los clientes, como cambio adicional aprobado.

Se espera revisión humana antes de crear el guion y ejecutar el bind o las repeticiones. Las consultas de diagnóstico no se han etiquetado como la revalidación completa LDAP-01..05, R1/R2. Para el bind se necesitará la contraseña de laboratorio de `ventas01`; no debe compartirse en el chat.
