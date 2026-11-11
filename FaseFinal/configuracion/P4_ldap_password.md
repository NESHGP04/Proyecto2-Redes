# P4 · Retomar y restablecer la contraseña de ventas01

**Estado actualizado:** el primer intento real falló en `slapmodify -u` con `Segmentation fault (core dumped)` y paquete `slapd 2.6.10+dfsg-0ubuntu0.24.04.1`. El servicio quedó activo y no se aplicó el cambio. El modo `cambiar` del método de este documento está deshabilitado en el repositorio. No repetirlo ni eliminar `-u` para forzar la escritura. El procedimiento histórico se conserva debajo para documentar el fallo. Ya se recibieron la identidad SASL y las ACL; la alternativa online está en [P4_ldap_password_local.md](P4_ldap_password_local.md), aprobada y ejecutada con éxito en AWS: recuperación, bind LDAPS y restauración de ACL confirmados a las 02:15:59 UTC del 11-nov-2026; evidencia `FINAL_LDAP-PASS_cambio_local_exitoso.txt`.

Solicitud del humano: 10 de noviembre de 2026. Nadie dispone de la contraseña de laboratorio; se autoriza preparar su restablecimiento y el encendido necesario.
El restablecimiento se limita a `uid=ventas01,ou=People,dc=zenite,dc=internal`, usado por el guion de demostración.

## Qué se puede recuperar

El directorio guarda un hash SSHA, no una contraseña consultable en texto claro. Si existe una copia conocida en el `.env` local del responsable, este puede consultarla privadamente.
Si se perdió, se establece una nueva; no se necesita descubrir la anterior.
Esta contraseña es de LDAP: no cambia los usuarios SSH `ubuntu`/`ec2-user` ni la cuenta IAM de AWS.

## 1. Encender para retomar · CloudShell

En la consola AWS selecciona **N. Virginia (`us-east-1`)** y abre **CloudShell**. El comando usa el script existente de P1 y enciende solo las tres instancias necesarias:

```bash
bash "$HOME/P1_instancias.sh" encender zp-ldap-01 zp-ventas-01 zp-ti-01
```

Si el script no está en CloudShell, subir `Fase3/configuracion/P1_instancias.sh` con **Actions → Upload file**.
Esperar los controles de estado de EC2 antes de conectar. Encender genera consumo de cómputo. No se necesita NAT para estas pruebas ni para la transferencia por EICE.

## 2. Copiar el guion · CloudShell

Subir con **Actions → Upload file** `FaseFinal/configuracion/P4_ldap_password.sh`.
Debe estar también `P3_eice.sh`, que ya se usó durante la sesión anterior. Si falta, subir `FaseFinal/configuracion/P3_eice.sh`.
Los archivos de CloudShell normalmente se conservan entre sesiones; no se reinstalan los servicios al encender EC2.

Este comando copia únicamente el guion al directorio personal de `ubuntu` en el servidor:

```bash
bash "$HOME/P3_eice.sh" zp-ldap-01 --copiar "$HOME/P4_ldap_password.sh"
```

Abrir la sesión del servidor:

```bash
bash "$HOME/P3_eice.sh" zp-ldap-01
```

El prompt debe identificar `ubuntu@zp-ldap-01`. A partir de aquí se trabaja **dentro del servidor**, no en CloudShell.
Como alternativa, usar EC2 → `zp-ldap-01` → Connect → EC2 Instance Connect Endpoint, usuario `ubuntu`.

## 3. Validar antes del cambio · zp-ldap-01

```bash
uname -n
```

Debe responder `zp-ldap-01`. El siguiente comando comprueba herramientas, IP, servicio, existencia de `ventas01` y certificado. No detiene LDAP ni cambia contraseñas:

```bash
sudo -n bash "$HOME/P4_ldap_password.sh" --validar
```

Si falla, conservar esa salida y detenerse antes del modo `cambiar`. No se instala ningún paquete automáticamente.

## 4. Establecer la nueva contraseña · zp-ldap-01

El siguiente comando inicia la recuperación solicitada. Antes de escribir, muestra su alcance y pide `si`:

```bash
sudo -n bash "$HOME/P4_ldap_password.sh" cambiar
```

Se introduce la nueva contraseña dos veces **sin eco**. No debe escribirse como argumento, pegarse en el chat ni aparecer en capturas.
La pausa del servicio sucede después de recibir y comprobar ambas entradas.

El procedimiento:

1. Genera un hash compatible con el directorio existente.
2. Detiene `slapd` y comprueba que no haya un proceso del servidor antes de abrir la base para escritura.
3. Guarda un respaldo privado de la base en `/root/final-config/P4_ldap_respaldo_<fecha>_<pid>/base.ldif`, con acceso solo para root.
4. Prepara la restauración del atributo anterior y simula la modificación con `slapmodify -u`.
5. Aplica únicamente el reemplazo de `userPassword` de `ventas01`, ejecutando la herramienta como `openldap` para conservar la identidad propietaria de los archivos.
6. Inicia el servicio y comprueba un bind por LDAPS con la nueva contraseña.

Si el bind o la modificación fallan, intenta restaurar el atributo anterior y volver a iniciar `slapd`. Si no puede confirmar la restauración o el inicio, informa el problema y la ruta privada del respaldo.
Las interrupciones gestionables activan la limpieza; SIGKILL o un apagado de la máquina requieren revisar el estado manualmente. No se promete recuperación automática frente a esos eventos.

El respaldo y `diagnostico-privado.txt` pueden contener hashes y detalles de recuperación: permanecen en el servidor, fuera del repositorio y de las capturas.
El guion elimina los archivos temporales de contraseña al terminar. No cambia `cn=admin`, los otros usuarios, certificados, firewall ni controles de acceso.
Una contraseña nueva reemplaza las anteriores de `ventas01`. Guardarla privadamente en el `.env` local ignorado por git; el guion no la imprime ni crea una copia local para el asistente.

El resultado esperado es `[OK] Contraseña de ventas01 cambiada y bind LDAPS confirmado` y `[OK] slapd activo al finalizar`.
La duración real y el resultado en AWS se registrarán cuando el humano comparta la salida; no se han supuesto.

## 5. Retomar la demostración

Volver a CloudShell desde el servidor:

```bash
exit
```

Entrar a Ventas:

```bash
bash "$HOME/P3_eice.sh" zp-ventas-01
```

En la terminal de Ventas:

```bash
uname -n
```

Esperado: `zp-ventas-01`. El guion de demo ya se copió durante la sesión anterior:

```bash
bash "$HOME/P4_ldap_demo.sh" demo
```

Introducir la contraseña nueva cuando se solicite de forma oculta. Repetir después desde TI para completar las tres consultas consecutivas desde cada subred.
LDAP-04 y R1/R2 siguen pendientes hasta recibir resultados reales. LDAP-05 requiere coordinar el encendido de Visitantes en su sesión de prueba.

## 6. Fuentes consultadas

- Ubuntu, `slappasswd`, generación y formato del hash: https://manpages.ubuntu.com/manpages/noble/man8/slappasswd.8.html
- Ubuntu, `slapmodify`, modificación fuera de línea, simulación e identidad del proceso: https://manpages.ubuntu.com/manpages/noble/man8/slapmodify.8.html
- Ubuntu, `slapcat`, exportación privada de la base: https://manpages.ubuntu.com/manpages/noble/man8/slapcat.8.html
- Ubuntu, `ldapwhoami`, comprobación del bind: https://manpages.ubuntu.com/manpages/noble/man1/ldapwhoami.1.html

La documentación advierte que `slapd` no debe ejecutarse durante `slapmodify`; por eso se pausa el servicio y se comprueba el proceso.

## Verificación local

Sintaxis del guion comprobada con `bash -n`. Se ejecutaron 13 escenarios con herramientas simuladas dentro de un contenedor aislado sin red:
preflight, cambio correcto, cancelación, contraseñas distintas, fallo de respaldo, fallo de simulación, fallo de escritura tras modificar,
bind fallido, bind anónimo, parada fallida, proceso aún activo, host incorrecto y respaldo con DN/base64/valores plegados.
Se comprobó el reinicio del servicio, la restauración del atributo en los fallos, los permisos y la limpieza de temporales, y que no se mostraran contraseña ni hash.
Se utilizó la identidad real `openldap` del contenedor para ejecutar las herramientas simuladas de base. No es una prueba de cambio real sobre OpenLDAP ni sobre AWS.
La compatibilidad y el resultado de la instancia se comprobarán con `--validar` y la salida real del cambio.

## Incidente real y siguiente diagnóstico de solo lectura

El humano confirmó la versión del paquete y leyó una salida redactada del diagnóstico privado. El único error mostrado fue `Segmentation fault (core dumped)`.
Esto acredita la caída durante la simulación; no identifica por sí solo su causa interna ni una incidencia concreta de OpenLDAP. Las pruebas simuladas no reprodujeron esta caída.

En `zp-ldap-01`, consultar la identidad local de root y las ACL de la base sin solicitar hashes:

```bash
sudo -n ldapwhoami -Q -Y EXTERNAL -H ldapi:///
```

```bash
sudo -n ldapsearch -Q -Y EXTERNAL -H ldapi:/// -LLL -o ldif_wrap=no -b cn=config '(olcSuffix=dc=zenite,dc=internal)' dn olcAccess
```

Estos comandos no cambian la contraseña, las ACL ni el servicio. La consulta incluye nombres de atributos en las reglas, no sus valores secretos.
Las salidas permitirán elegir una operación local con permisos comprobados. Un permiso de root sobre `cn=config` no demuestra automáticamente permiso de escritura sobre los usuarios del directorio.
