# Recuperar ventas01 por LDAP local

Estado: **opción A ejecutada con éxito en AWS**. La salida recibida confirma el cambio de `ventas01`, el bind por LDAPS, la retirada del permiso temporal, las tres ACL originales y `slapd` activo el 11-nov-2026 a las 02:15:59 UTC (10-nov, 20:15:59 Guatemala). Evidencia: `FINAL_LDAP-PASS_cambio_local_exitoso.txt`. No repetir el restablecimiento para continuar: usar la contraseña nueva en la demo desde Ventas y TI. El intento offline anterior falló en la simulación; no reutilizar `P4_ldap_password.sh cambiar`.

## Alcance para revisión

La salida recibida confirma la identidad de root por SASL EXTERNAL y estas reglas en `olcDatabase={1}mdb,cn=config`:

```ldif
olcAccess: {0}to attrs=userPassword by self write by anonymous auth by * none
olcAccess: {1}to attrs=shadowLastChange by self write by * read
olcAccess: {2}to * by * read
```

La primera permite a cada usuario cambiar su contraseña, pero no concede esa escritura a la identidad EXTERNAL de root. No se puede obtener la contraseña original a partir del hash; se propone establecer una nueva.

**Opción A, recomendada:** ejecutar `P4_ldap_password_local.sh cambiar`. Inserta temporalmente esta regla al principio, manteniendo las tres originales:

```ldif
olcAccess: {0}to dn.exact="uid=ventas01,ou=People,dc=zenite,dc=internal" attrs=userPassword by dn.exact="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" write by * break
```

El permiso corresponde únicamente a root local y al atributo `userPassword` de `ventas01`. Los demás accesos continúan evaluando las reglas originales. Respalda ese atributo de forma privada, aplica `ldappasswd` por `ldapi:///`, prueba el bind por LDAPS con CA explícita y elimina la regla temporal por su valor completo, sin usar su posición. Solo informa éxito si se confirman el bind, las tres reglas originales y el servicio activo. No detiene el servicio.

Esta opción **sí modifica brevemente una ACL de OpenLDAP**. Es una desviación del método anterior, que prometía no cambiar reglas. El humano ya aprobó este alcance conforme a R3 del documento P4 y su apartado 6.1. No cambia SG/NACL de AWS, recursos de P3, `cn=admin` ni certificados.

**Opción B:** conservar LDAP como está y aplazar el bind hasta obtener una credencial válida del responsable. Las lecturas LDAP-01..03 ya recibidas se conservan; el checkpoint 3 seguirá abierto.

## Desde el navegador: preparación y validación de solo lectura

1. En AWS, región **N. Virginia / us-east-1**, abre CloudShell. Si las instancias están apagadas, inicia las tres necesarias con el script existente de P1:

   ```bash
   bash "$HOME/P1_instancias.sh" encender zp-ldap-01 zp-ventas-01 zp-ti-01
   ```

   Espera los controles de estado y la disponibilidad de EICE. No hace falta iniciar el monitor ni crear un NAT para esta operación.

2. En CloudShell, **Actions → Upload file**, sube `P4_ldap_password_local.sh`. El humano usa Fedora: en el selector del navegador abre la carpeta de su repositorio local y entra a `FaseFinal/configuracion`. Selecciona el archivo que termina en **`_local.sh`**. No se necesita WSL. Este procedimiento ya se ejecutó con éxito; no repetir el cambio de contraseña para revisar su evidencia.

3. En la terminal de **CloudShell** (`~ $`), copia y valida:

   ```bash
   bash "$HOME/P3_eice.sh" zp-ldap-01 --copiar "$HOME/P4_ldap_password_local.sh"
   bash "$HOME/P3_eice.sh" zp-ldap-01 'sudo -n bash "$HOME/P4_ldap_password_local.sh" --validar'
   ```

   `--validar` consulta servicio, identidad, base, reglas, usuario y certificado; solo escribe su registro privado. No inserta la ACL ni lee una contraseña. Debe terminar con `[OK] Validación terminada; no se modificaron LDAP ni slapd`. Si aparece una falla, comparte únicamente la salida pública.

## Ejecutar la opción A aprobada

1. Desde CloudShell abre una sesión interactiva:

   ```bash
   bash "$HOME/P3_eice.sh" zp-ldap-01
   ```

2. Ya en **`ubuntu@zp-ldap-01`**, ejecuta:

   ```bash
   sudo -n bash "$HOME/P4_ldap_password_local.sh" cambiar
   ```

   Revisa el alcance, escribe `si` y escribe dos veces la nueva contraseña. La entrada es oculta; cada pregunta tiene un límite de 120 s. No la pegues en el chat ni en un comando. La contraseña de LDAP es distinta de la del usuario Ubuntu.

3. El éxito esperado es el siguiente; estos mensajes ya fueron recibidos de la ejecución real en AWS y están conservados en la evidencia indicada arriba:

   ```text
   [OK] Permiso temporal retirado; las tres ACL originales coinciden
   [OK] slapd sigue activo
   [OK] Contraseña de ventas01 cambiada, bind LDAPS confirmado y ACL originales restauradas
   ```

4. Guarda la contraseña en tu gestor o `.env` local ignorado por git. Comparte la salida pública. Escribe `exit` para volver a CloudShell y continúa la demo desde Ventas:

   ```bash
   bash "$HOME/P3_eice.sh" zp-ventas-01 'bash "$HOME/P4_ldap_demo.sh" demo'
   ```

   El guion pedirá la nueva contraseña de forma oculta. Después repite desde `zp-ti-01` siguiendo `P4_ldap_demo.md`. Estas pruebas y Visitantes aún son necesarias; el cambio de contraseña por sí solo no cierra el checkpoint.

## Respaldo, fallos y limpieza

- Cada corrida usa un directorio privado `/root/final-config/P4_ldap_local_<hora>_<aleatorio>/`: carpeta 700, archivos 600, resultado público separado de diagnóstico privado. Un bloqueo local impide ejecutar dos recuperaciones a la vez.
- El respaldo del atributo y `restaurar-password.ldif` **contienen hashes sensibles**. No subir esa carpeta al repositorio ni mostrar su contenido. El archivo temporal con la contraseña nueva se elimina al salir; el respaldo del hash anterior se conserva.
- Ante un fallo de cambio/bind, intenta restaurar el atributo anterior y comprueba su igualdad; después intenta retirar la regla. Ante respuesta perdida o SIGINT/SIGTERM también comprueba y limpia. Cada comando tiene 12 s de límite.
- Si encuentra cambios de otro administrador, elimina solo su propia regla y falla si las ACL restantes difieren del respaldo. No reemplaza el conjunto completo de reglas. Coordina una ventana sin cambios LDAP simultáneos.
- Una pérdida de energía, `SIGKILL` o fallo del servidor puede impedir la limpieza. Si no se confirma la retirada, **no repitas cambiar ni apagues la instancia todavía**. Conserva la ruta del respaldo y consulta las reglas con el comando siguiente, que no muestra contraseñas:

  ```bash
  sudo -n ldapsearch -Q -Y EXTERNAL -H ldapi:/// -LLL -o ldif_wrap=no \
    -b 'olcDatabase={1}mdb,cn=config' -s base olcAccess
  ```

  Si sigue presente exactamente la regla temporal descrita arriba, `retirar-permiso.ldif` permite borrarla por su valor, sin índice. Revisa primero su alcance; luego, en la instancia, sustituye el directorio por el impreso por tu corrida:

  ```bash
  sudo -n ldapmodify -Q -Y EXTERNAL -H ldapi:/// \
    -f '/root/final-config/P4_ldap_local_DIRECTORIO_DE_TU_CORRIDA/retirar-permiso.ldif'
  ```

  Repite la consulta de ACL. Si falta ese archivo o la regla no coincide, solicita revisión en lugar de improvisar una sustitución de ACL. La contraseña podría haberse cambiado antes de la interrupción; no se debe asumir restauración automática.

## Comprobación local y límites

Se probaron nueve escenarios con un servidor OpenLDAP real, paquete `2.6.10+dfsg-0ubuntu0.24.04.1`, en un contenedor Ubuntu 24.04 sin puertos publicados. La copia de prueba usa loopback y certificado efímero; se sustituye únicamente la consulta a systemd porque el contenedor no lo ejecuta. Las operaciones de configuración, contraseña, lectura y TLS usan herramientas y servidor reales. Para los casos de fallo se inyectan errores alrededor de esas herramientas.

Se comprobaron: validación sin cambios; cambio/bind correctos conservando otros usuarios y `olcRootPW`; restauración ante fallo de bind; cambio aplicado con respuesta fallida; ACL añadida con respuesta fallida; interrupción; alcance limitado al usuario y confidencialidad frente a anónimos; preservación de una ACL concurrente sin falso éxito; rechazo de una configuración inicial distinta. Se comprobaron permisos privados, eliminación del temporal y ausencia de la contraseña sintética en la terminal. Se conserva el resumen en `FINAL_LDAP-PASS_pruebas_locales.txt`.

Durante las pruebas se comprobó que el backend `cn=config` rechaza el control crítico `assert` con código 12. La versión entregada no lo usa: agrega una sola regla y elimina por valor completo; nunca sustituye `olcAccess`. Esto no ofrece una transacción que abarque toda la recuperación; los cambios simultáneos se detectan y se informa el conflicto.

Estas pruebas locales **no son resultados de las instancias AWS**. La ejecución real recibida posteriormente está documentada por separado en `FINAL_LDAP-PASS_cambio_local_exitoso.txt`: confirma la recuperación y el bind desde el servidor. Las demos posteriores desde Ventas y TI también se recibieron completas y exitosas; ver `FINAL_LDAP-04_ventas_bind.txt` y `FINAL_LDAP-R2_ti.txt`. La prueba negativa desde Visitantes también pasó, con controles positivos de Ventas antes y después; ver `FINAL_LDAP-05_visitantes_bloqueado.txt` y `FINAL_LDAP-05_control_ventas.txt`. No repetir el restablecimiento para continuar.

Referencias: [orden de ACL de OpenLDAP](https://www.openldap.org/doc/admin26/access-control.html#Access%20Control%20Ordering), [ldappasswd de Ubuntu 24.04](https://manpages.ubuntu.com/manpages/noble/man1/ldappasswd.1.html).
