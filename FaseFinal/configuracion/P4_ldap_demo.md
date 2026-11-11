# P4 · LDAP: guion con CA explícita y revalidación

Checkpoint 3 revisado: LDAP-01..05 y R2 con PASS real; R1 como escenario representativo, con limitación histórica declarada. El humano aprobó CA explícita por comando, sin instalar confianza global, y la recuperación local de contraseña con permiso temporal ya retirado. Después pidió «hagamos todo», autorizando continuar al diseño del checkpoint 4. Resumen: [P4_ldap_checkpoint3.md](P4_ldap_checkpoint3.md).
Las consultas LDAPS, el bind y las repeticiones ya tienen resultados reales correctos; véase la tabla de revalidación.

## Qué hace `P4_ldap_demo.sh`

| Modo / origen | Comprobaciones |
|---|---|
| `--validar` en `zp-ldap-01` | Host/IP, certificado aprobado y vigente para `10.20.0.69`, `slapd` activo, escucha 389/636, cuatro usuarios y dos grupos con miembros correctos por LDAP y LDAPS. |
| `--validar` en `zp-ventas-01` o `zp-ti-01` | Host/IP, certificado y árbol completo por 389 y 636. No necesita contraseña. |
| `demo` en Ventas o TI | Validación previa, bind de `ventas01`, rechazo de contraseña incorrecta, rechazo de usuario inexistente y tres búsquedas autenticadas consecutivas. |

El guion usa exclusivamente LDAPS para cualquier bind con contraseña. El tráfico por 389 es lectura anónima para repetir las pruebas de Fase 3.
Cada operación tiene un máximo de 10 s, con hasta 2 s para terminarla; el presupuesto conjunto es 110 s, incluida la entrada oculta de contraseña (hasta 20 s).
Un error detiene el guion con `[FALLA]`, su paso y el código recibido. Solo el código **49** acredita rechazo de credenciales.
El tiempo real de la demo en AWS sigue por medir. El límite de ejecución es una protección, no una medición de su duración real.

La huella del certificado se fija a la ya verificada en servidor, TI, Ventas y repositorio. Si se renueva, hay que coordinar y actualizar esa huella; el guion no acepta silenciosamente un certificado distinto.

## 1. Copiar y validar desde el navegador

En **AWS CloudShell, N. Virginia**, sube con **Actions → Upload file**:

1. `FaseFinal/configuracion/P4_ldap_demo.sh`.
2. `FaseFinal/configuracion/P3_eice.sh`, el ayudante existente de P3, que se reutiliza sin modificar.

El humano usa Fedora: en el selector de archivos del navegador abre la carpeta del repositorio local y selecciona `FaseFinal/configuracion/P4_ldap_demo.sh`. No se necesita WSL ni instalar paquetes en las instancias para la transferencia por EICE desde CloudShell.

Los comandos de copia escriben únicamente `P4_ldap_demo.sh` en el directorio personal de cada instancia. Reemplazan una copia anterior del mismo guion si existe.
El ayudante de P3 usa autenticación por EICE y conserva su llave en CloudShell; no se comparte ni se copia esa llave al repositorio.
El guion de P4 no configura servicios, firewall, usuarios, contraseñas o confianza global.

Ejecuta **un comando por vez** en CloudShell, esperando a que regrese el prompt:

```bash
bash "$HOME/P3_eice.sh" zp-ventas-01 --copiar "$HOME/P4_ldap_demo.sh"
```

```bash
bash "$HOME/P3_eice.sh" zp-ventas-01 'bash "$HOME/P4_ldap_demo.sh" --validar'
```

```bash
bash "$HOME/P3_eice.sh" zp-ti-01 --copiar "$HOME/P4_ldap_demo.sh"
```

```bash
bash "$HOME/P3_eice.sh" zp-ti-01 'bash "$HOME/P4_ldap_demo.sh" --validar'
```

```bash
bash "$HOME/P3_eice.sh" zp-ldap-01 --copiar "$HOME/P4_ldap_demo.sh"
```

```bash
bash "$HOME/P3_eice.sh" zp-ldap-01 'bash "$HOME/P4_ldap_demo.sh" --validar'
```

Las tres instancias ya fueron encendidas por el humano. Ante errores de permisos o conexión, conservar el error; no cambiar reglas para resolverlo sin diagnóstico.
Si SSH informa un cambio de identidad, coordinarlo con P1. El ayudante rechaza una huella conocida que cambió.

Esperado: en cada host, cuatro usuarios, dos grupos, miembros correctos y validación terminada. Se registra la hora real y el código de cada comando.
Los TXT quedan en `~/final-config/` **dentro de cada instancia**. No son los registros de CloudShell.

## 2. Contraseña de laboratorio y bind

El humano restableció correctamente la contraseña de `ventas01` mediante [P4_ldap_password_local.md](P4_ldap_password_local.md). La salida real de AWS confirma bind LDAPS desde el servidor, retirada del permiso temporal, tres ACL originales restauradas y servicio activo el 11-nov-2026 a las 02:15:59 UTC (10-nov 20:15:59 Guatemala). Evidencia: `FINAL_LDAP-PASS_cambio_local_exitoso.txt`. Usar la contraseña nueva; no repetir el restablecimiento. El primer método offline falló y permanece deshabilitado.
Puede conservarla en su `.env` local, ignorado por git. No se sube ese archivo a CloudShell ni se comparte en el chat o capturas.
No se requiere la contraseña del administrador LDAP para estas pruebas.

Con la contraseña nueva disponible, en **EC2 → Instances → `zp-ventas-01` → Connect → EC2 Instance Connect Endpoint**, usuario **`ec2-user`**:

```bash
uname -n
```

Esperado: `zp-ventas-01`. Después:

```bash
bash "$HOME/P4_ldap_demo.sh" demo
```

El guion solicitará la contraseña de forma oculta. Introducirla dentro del plazo cuando aparezca el prompt.
No escribirla como argumento del comando. No ejecutar la demo con una contraseña inventada para intentar aprobar el bind correcto.

El guion evita trazas de shell, no carga `.env`, no imprime la contraseña y no la pasa a las herramientas LDAP como argumento.
Para `-y` crea archivos temporales 0600 en un directorio privado, los elimina al terminar o ante señales gestionables, y guarda solo resultados en el log.
La finalización forzada con SIGKILL no permite ejecutar limpieza; no se presume una eliminación segura física del almacenamiento.
También admite `LDAP_USER_PASSWORD` si el humano ya la tiene cargada en su entorno privado; se elimina del entorno antes de lanzar las herramientas hijas.
El uso interactivo es el recomendado para el navegador.

Repetir el mismo `demo` desde **`zp-ti-01`**, también como `ec2-user`, para obtener tres búsquedas autenticadas consecutivas desde cada subred.
La demostración de usuario inexistente es adicional al rechazo de contraseña incorrecta sobre `ventas01`.

## 3. Prueba de Visitantes: encendido temporal aprobado

El humano aprobó la opción A para encender únicamente `zp-visitantes-01`, probar el bloqueo y detenerla al terminar. **La prueba ya pasó**: TCP 389/636 con exit 124 y consulta LDAP fallida con exit 255 entre 11-nov-2026 02:30:17–02:30:32 UTC; controles de Ventas correctos antes y después. Evidencias `FINAL_LDAP-05_visitantes_bloqueado.txt` y `FINAL_LDAP-05_control_ventas.txt`. **Apagado confirmado** posteriormente por P1 y estado `stopped`, guardado en `FINAL_LDAP-05_visitantes_apagado.txt`. No repetir la prueba ni el encendido para revisar estos resultados. El procedimiento siguiente se conserva para una futura repetición autorizada.
Mientras se prueba Visitantes, mantener LDAP y Ventas encendidas. Los controles positivos de Ventas antes y después permiten distinguir el bloqueo de un servidor apagado o averiado.

Si estás conectado a TI, ejecutar `exit` una vez para regresar a **CloudShell** (`~ $`). Allí encender únicamente Visitantes:

```bash
bash "$HOME/P1_instancias.sh" encender zp-visitantes-01
```

Esperar los controles de estado de la instancia en EC2 y la disponibilidad de EICE. No intentar resolver una espera de arranque cambiando las reglas de red.

En **CloudShell**, comprobar el control positivo desde Ventas y, solo si termina correctamente, conectar a Visitantes:

```bash
bash "$HOME/P3_eice.sh" zp-ventas-01 'bash "$HOME/P4_ldap_demo.sh" --validar'
bash "$HOME/P3_eice.sh" zp-visitantes-01
```

Ya en **`ec2-user@zp-visitantes-01`**, confirmar:

```bash
uname -n
```

Esperado: `zp-visitantes-01`. Registrar la hora:

```bash
date -u
```

Comprobar TCP 389 y 636; se espera agotamiento del tiempo, código 124:

```bash
timeout --kill-after=2s 5s bash -c 'exec 3<>/dev/tcp/10.20.0.69/389'; printf 'TCP389 exit=%s\n' "$?"
```

```bash
timeout --kill-after=2s 5s bash -c 'exec 3<>/dev/tcp/10.20.0.69/636'; printf 'TCP636 exit=%s\n' "$?"
```

Repetir la consulta anónima de LDAP-05, sin contraseña:

```bash
timeout --kill-after=2s 10s ldapsearch -x -LLL -o nettimeout=5 -l 5 -H ldap://10.20.0.69 -b dc=zenite,dc=internal '(uid=*)' uid
printf 'ldapsearch exit=%s\n' "$?"
```

El último comando debe ejecutarse inmediatamente después de `ldapsearch`. `nettimeout` puede devolver 255 antes de que actúe el `timeout` exterior; el código aislado no demuestra bloqueo.
Contrastar los dos puertos, las reglas ya recogidas y un `--validar` exitoso desde Ventas en esa misma ventana. Si el control positivo falla, LDAP-05 no queda aprobada.

Si `ldapsearch` no está instalado (salida `command not found`/127), no es evidencia de bloqueo LDAP. Conservar el resultado de las conexiones TCP y compartir el error; no instalar paquetes ni iniciar NAT por ese fallo.

Al finalizar, ejecutar `exit` en Visitantes para volver a **CloudShell**, repetir el control positivo y detener únicamente Visitantes:

```bash
bash "$HOME/P3_eice.sh" zp-ventas-01 'bash "$HOME/P4_ldap_demo.sh" --validar'
bash "$HOME/P1_instancias.sh" detener zp-visitantes-01
```

Compartir las salidas de Visitantes, ambos controles de Ventas y el apagado. Guardar capturas donde se vean hostname/prompt, comandos, salida y hora. El apagado al terminar ya está autorizado, también si la prueba queda inconclusa; no detener LDAP/Ventas/TI con este paso.

Para completar el registro de salud EC2, ejecutar en **CloudShell** esta consulta de solo lectura mientras LDAP/Ventas/TI sigan encendidas:

```bash
date -u
aws ec2 describe-instance-status --region us-east-1 --include-all-instances \
  --instance-ids i-04f9cc2b9ee3f77cd i-0f3bd7b0615933e00 i-0378a8624df39958b \
  --query 'InstanceStatuses[].{ID:InstanceId,Estado:InstanceState.Name,Sistema:SystemStatus.Status,Instancia:InstanceStatus.Status,EBS:AttachedEbsStatus.Status}' \
  --output table
```

Se esperan tres filas `running` con estado `ok` en sistema, instancia y EBS. Un campo vacío se registra como dato no disponible; no se inventa un PASS ni se cambia configuración. Los checks EC2 son distintos de las búsquedas LDAP repetidas.
La salida real ya fue recibida: las tres instancias están `running` y muestran `ok` en las tres columnas. Hora de `date` previo a la consulta: 11-nov-2026 02:35:01 UTC / 10-nov 20:35:01 Guatemala. Evidencia `FINAL_LDAP-EC2_salud_final.txt`.

## 4. Filas preparadas, sin resultados inventados

| ID | Qué se requiere para cerrarla | Estado de la revalidación |
|---|---|---|
| LDAP-01 | `--validar` en servidor: servicio, puertos, certificado y árbol. | **PASS real**, 9-nov-2026 20:23:01–20:23:02 Guatemala: `slapd` activo, escucha 389/636, certificado verificado y árbol correcto; comandos exit 0. Evidencia `FINAL_LDAP-01_servidor_validar.txt`. |
| LDAP-02 | `--validar` en Ventas por 389 y 636. | **PASS real**, 9-nov-2026 20:19:24 Guatemala: cuatro usuarios y dos grupos, miembros correctos, certificado verificado; todos los comandos exit 0. Evidencia `FINAL_LDAP-02_ventas_validar.txt`. |
| LDAP-03 | `--validar` en TI por 389 y 636. | **PASS real**, 9-nov-2026 20:22:37 Guatemala: cuatro usuarios y dos grupos, miembros correctos, certificado verificado; comandos exit 0. Evidencia `FINAL_LDAP-03_ti_validar.txt`. |
| LDAP-04 | `demo` en Ventas: DN correcto y rechazo con exit 49. | **PASS real**, 10-nov-2026 20:18:33 Guatemala: DN de `ventas01` con exit 0 y contraseña incorrecta rechazada con exit 49; usuario inexistente también rechazado con 49. Evidencia `FINAL_LDAP-04_ventas_bind.txt`. |
| LDAP-05 | Visitantes bloqueado con control positivo de Ventas durante la misma ventana. | **PASS real**, 10-nov-2026 20:30:17–20:30:32 Guatemala: TCP 389/636 exit 124 y consulta LDAP exit 255 sin usuarios. Ventas lee por ambos puertos antes y después, 20:29:44 y 20:31:19. Evidencias `FINAL_LDAP-05_visitantes_bloqueado.txt` y `FINAL_LDAP-05_control_ventas.txt`. Visitantes apagada después: `FINAL_LDAP-05_visitantes_apagado.txt`. |
| LDAP-R1 | Escenario representativo de demostración por LDAPS con CA explícita y bind. | Escenario representativo **PASS real desde Ventas y TI**: demos completadas en 7 s y 6 s, respectivamente. Evidencias `FINAL_LDAP-04_ventas_bind.txt` y `FINAL_LDAP-R2_ti.txt`. El comando histórico sigue desconocido: no se afirma haberlo repetido exactamente. |
| LDAP-R2 | Tres búsquedas autenticadas consecutivas en Ventas y tres en TI, con el mismo comando del guion. | **PASS real: Ventas 3/3 y TI 3/3**, exit 0 y árbol completo. Ventas: 10-nov-2026 20:18:33 Guatemala, `FINAL_LDAP-04_ventas_bind.txt`; TI: 20:24:01 Guatemala, `FINAL_LDAP-R2_ti.txt`. Los seis comandos coinciden salvo la ruta aleatoria del fichero privado. Se conserva el primer intento fallido en `FINAL_LDAP-R2_ti_intento1_timeout_entrada.txt`. |

La matriz global la mantiene P5. No se han asignado PASS a estas filas a partir de simulaciones.
Los TXT deben conservar fallos y repeticiones; una corrida posterior no borra el primer intento.

## 5. Evidencias y demostración

Guardar salidas y capturas reales en `FaseFinal/evidencias/04_snmp_ldap/`:

- `FINAL_LDAP-01_servidor_validar.txt` / `.png`: hostname, hora, servicio, puertos, certificado y árbol.
- `FINAL_LDAP-02_ventas_validar.txt` / `.png` y `FINAL_LDAP-03_ti_validar.txt` / `.png`.
- `FINAL_LDAP-04_ventas_bind.txt` / `.png`: DN válido y rechazos exit 49, sin contraseña visible.
- `FINAL_LDAP-05_visitantes_bloqueado.txt` / `.png`, más la validación de Ventas como control positivo.
- `FINAL_LDAP-R1_demo.txt` / `.png` y `FINAL_LDAP-R2_ventas.txt` / `.png`, `FINAL_LDAP-R2_ti.txt` / `.png`.

Una misma corrida puede aportar a varias pruebas; documentar cuáles cubre y su hora real, sin fabricar archivos distintos como si fueran nuevas ejecuciones.
La demo real de Ventas se conserva completa en `FINAL_LDAP-04_ventas_bind.txt`; ese único archivo respalda también el escenario representativo de R1 y las tres repeticiones de Ventas de R2. No se duplicó como si fueran otras corridas. La captura `demo.png` aportada por el humano permanece sin evaluar en esta revisión del registro de texto.
La segunda demo de TI se conserva completa en `FINAL_LDAP-R2_ti.txt`: inicio 11-nov-2026 02:23:55 UTC, fin 02:24:01 UTC. Acredita bind válido, rechazos y tres búsquedas autenticadas. El primer intento de TI sigue conservado por separado. En el adjunto también se ve una ejecución del guion desde CloudShell que falla por falta de `ldapsearch`: no se usa como fallo de TI ni requiere instalar el cliente en CloudShell; `demo` se ejecuta dentro de Ventas/TI.
Para recuperar un log se puede usar `cat` en la terminal del host y copiar su contenido; el guion muestra la ruta exacta.
Plan B: abrir los TXT y capturas de una corrida real ya validada y explicar que son evidencia guardada. Las salidas del diagnóstico actual no sustituyen una prueba de bind que aún no existe.

Guion en vivo: confirmar hostname, ejecutar `demo`, mostrar bind correcto, exit 49 en los rechazos, grupos y consultas 3/3; después mostrar el registro de la otra subred.
Si falla un paso, conservar la salida y usar el plan B, sin modificar reglas en plena demostración.

## 6. Fuentes consultadas

- Manual oficial publicado por Ubuntu, `ldapsearch`: https://manpages.ubuntu.com/manpages/noble/man1/ldapsearch.1.html
- Manual oficial publicado por Ubuntu, `ldapwhoami`: https://manpages.ubuntu.com/manpages/noble/man1/ldapwhoami.1.html
- Manual oficial publicado por Ubuntu, confianza TLS y precedencia del entorno: https://manpages.ubuntu.com/manpages/noble/man5/ldap.conf.5.html
- OpenSSL, verificación de IP y propósito: https://docs.openssl.org/3.0/man1/openssl-verification-options/
- AWS, conexión por EICE: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html

Las opciones `timeout --kill-after` y sus códigos se contrastan además con `timeout --help` en el entorno local. La página de GNU no respondió a la herramienta de consulta durante esta sesión.

## 7. Verificación local y sus límites

- `bash -n` correcto para el guion y para los 14 bloques Bash de esta guía.
- **19 escenarios con herramientas simuladas:** lectura desde Ventas, demo desde TI, host ajeno, IP ajena, certificado ausente, huella distinta, árbol incompleto, miembros incorrectos, error TLS, contraseña válida rechazada, respuesta anónima en lugar del DN, timeout en una prueba negativa, contraseña incorrecta aceptada, usuario inexistente aceptado, fallo en la segunda repetición, lectura del servidor, `slapd` inactivo, ausencia del listener 636 y espera real limitada por `timeout`.
- **2 pruebas de terminal interactiva simuladas:** contraseña correcta introducida sin eco y entrada vacía rechazada. Se comprobó que la contraseña sintética no aparece en la terminal ni en los registros.
- En los escenarios que crean temporales se comprobó modo 0600 para archivos, 0700 para el directorio y eliminación al salir. Las herramientas hijas no recibieron `LDAP_USER_PASSWORD` ni la variable privada usada por el guion.
- **Integración parcial con OpenLDAP real local:** `--validar` leyó el árbol por LDAP/LDAPS y verificó un certificado efímero. Se usó una copia de prueba con dirección loopback y huella del certificado de prueba; el guion del repositorio conserva IP y huella reales del proyecto.
- La demo autenticada de esa integración **no se aprobó**: hubo errores de credenciales al preparar/probar el directorio sintético. Se ajustó el montaje de las credenciales de prueba, pero la nueva preparación agotó 180 s descargando dependencias y no permitió completar la repetición. Los contenedores de prueba se eliminaron.

Las comprobaciones locales de esta sección no son resultados de AWS. La revalidación real se mantiene en la sección 4: LDAP-01 a LDAP-05 y LDAP-R2 ya fueron recibidas como PASS, junto con el escenario representativo de R1 desde ambas subredes. El apagado de Visitantes y la salud EC2 de LDAP/Ventas/TI ya tienen evidencia. Los controles de estado EC2 3/3 no deben confundirse con las repeticiones LDAP 3/3 ni con sincronización NTP. La prueba histórica exacta de R1 sigue sin conocerse; se presenta esta limitación para la aprobación del checkpoint.
