# Checkpoint 3 · LDAP recuperado y revalidado

**Estado: cierre revisado; el humano pidió «hagamos todo» y autorizó continuar al checkpoint 4.** Se conserva explícitamente que R1 es representativo y que el comando histórico sigue desconocido. Se prepara el diseño SNMP, que necesita su propia elección y aprobación antes de desplegar.

## 1. Qué hice

- Implementé la demo con CA explícita, verificación TLS, tiempos límite y registros: árbol, bind, rechazos y repeticiones.
- Preparé y acompañé la recuperación autorizada de `ventas01`; el humano la ejecutó en AWS y se confirmaron bind y retirada del permiso temporal.
- Revisé salidas reales de servidor, Ventas, TI y Visitantes y conservé tanto éxitos como intentos fallidos.
- Comprobé el apagado final de Visitantes y la salud EC2 de LDAP, Ventas y TI a partir de las salidas recibidas.

La dependencia de confianza explícita se reprodujo en los clientes actuales: sin fijar CA la consulta falló, con CA explícita funcionó. **La causa exacta de la demostración histórica sigue sin confirmarse**, pues el humano no conoce su comando ni error. No se presenta esa hipótesis como hecho histórico.

## 2. Archivos creados o modificados

Dentro de `FaseFinal/configuracion/`:

- `P4_ldap_demo.sh` y `P4_ldap_demo.md`: demo y guía con tabla de resultados lista para P5.
- `P4_ldap_password_local.sh` y `P4_ldap_password_local.md`: recuperación online autorizada y probada.
- `P4_ldap_password.sh` y `P4_ldap_password.md`: método offline histórico; `cambiar` deshabilitado tras la caída real de la simulación.
- `P4_ldap_diagnostico.md`: hallazgos del diagnóstico; el guion de consulta `P4_ldap_diagnostico.sh` ya estaba versionado.
- `P4_ldap_checkpoint3.md`: esta revisión.

También se actualizó `FaseFinal/bitacora/P4.md` y se agregaron los TXT `FINAL_LDAP*.txt` del checkpoint en `FaseFinal/evidencias/04_snmp_ldap/`. Las evidencias históricas del diagnóstico ya versionadas se conservan. Las capturas aportadas por el humano no fueron modificadas ni verificadas visualmente en esta revisión textual.

No se modificaron scripts de P1/P3 ni la matriz compartida de P5. Los respaldos con hashes permanecen en `/root/final-config/` de la instancia, fuera del repositorio.

## 3. Cómo revisarlo y probarlo

No hace falta ejecutar más comandos en AWS para revisar estos resultados. Abrir la tabla de `P4_ldap_demo.md` y contrastar:

| Prueba | Resultado real | Evidencia en `FaseFinal/evidencias/04_snmp_ldap/` |
|---|---|---|
| LDAP-01 | Servicio activo, puertos, certificado y árbol correctos en servidor. | `FINAL_LDAP-01_servidor_validar.txt` |
| LDAP-02 | Lectura desde Ventas por 389 y 636 correcta. | `FINAL_LDAP-02_ventas_validar.txt` |
| LDAP-03 | Lectura desde TI por 389 y 636 correcta. | `FINAL_LDAP-03_ti_validar.txt` |
| LDAP-04 | DN válido con exit 0; contraseña errónea y usuario inexistente con exit 49. | `FINAL_LDAP-04_ventas_bind.txt` |
| LDAP-05 | TCP 389/636 exit 124; consulta LDAP exit 255 sin usuarios, entre controles positivos de Ventas. | `FINAL_LDAP-05_visitantes_bloqueado.txt`, `FINAL_LDAP-05_control_ventas.txt` |
| LDAP-R1 representativo | Demos por LDAPS con CA explícita desde Ventas/TI en 7 s y 6 s. Equivalencia histórica no verificable. | Misma corrida de LDAP-04 y `FINAL_LDAP-R2_ti.txt` |
| LDAP-R2 | Tres búsquedas consecutivas desde cada subred; seis comandos iguales salvo fichero privado aleatorio, todos exit 0 y árbol completo. | `FINAL_LDAP-04_ventas_bind.txt`, `FINAL_LDAP-R2_ti.txt` |

La recuperación real y restauración de las tres ACL originales constan en `FINAL_LDAP-PASS_cambio_local_exitoso.txt` (11-nov-2026 02:15:59 UTC / 10-nov 20:15:59 Guatemala).

Salud final: `FINAL_LDAP-EC2_salud_final.txt`, `date` previo a consulta 11-nov-2026 02:35:01 UTC / 10-nov 20:35:01 Guatemala; sistema, instancia y EBS en `ok` para LDAP/Ventas/TI. `FINAL_LDAP-05_visitantes_apagado.txt` confirma Visitantes `stopped`. El apagado no tiene una hora exacta en su salida. Permanecen tres instancias encendidas; el monitor sigue detenido según el resumen recibido.

El guion ya pasó las comprobaciones locales descritas en su guía y después las demos reales. No se repitieron pruebas de autenticación por cambios exclusivamente documentales. Se comprobaron sintaxis de los bloques Bash, referencias locales y ausencia de errores de espacios en esta entrega.

Para una futura repetición autorizada, ejecutar `bash "$HOME/P4_ldap_demo.sh" demo` **dentro de Ventas o TI**, con la contraseña nueva preparada para introducirla de forma oculta en 20 s. No ejecutar `demo` en CloudShell ni volver a restablecer la contraseña para repetir la demo. Para plan B, abrir las salidas guardadas y declarar su procedencia y fecha.

## 4. Evidencia a capturar para la presentación

Los TXT contienen evidencia real completa suficiente para revisar los resultados. Para completar capturas de la entrega final, el humano puede mostrar los TXT guardados, indicando que son evidencia de esas corridas; no hace falta reabrir Visitantes solo para tomar una imagen:

- `FINAL_LDAP-04_ventas_bind.png`: hostname, hora, DN correcto y ambos rechazos con exit 49.
- `FINAL_LDAP-R2_ti.png`: hostname TI, hora y repeticiones 1/3, 2/3 y 3/3.
- `FINAL_LDAP-05_visitantes_bloqueado.png`: hostname Visitantes, comandos, horas, TCP exit 124 y consulta fallida; acompañar con los controles de Ventas.
- `FINAL_LDAP-EC2_salud_final.png`: tres instancias y tres checks en `ok`; si se usa consola EC2, incluir región N. Virginia. Conservar también la salida de apagado.

No mostrar contraseñas, `.env`, hashes ni contenido de los respaldos privados. No se asigna PASS a una imagen que no se haya revisado.

## 5. Problemas y límites

- `slapmodify -u` cayó con `Segmentation fault (core dumped)` en el primer intento real; la escritura no se intentó y el servicio quedó activo. No se conoce el defecto interno. Método retirado, fallo conservado.
- La alternativa online añadió una ACL temporal, limitada a root local y a `userPassword` de `ventas01`, con autorización explícita. La salida real confirma que se retiró y se restauraron las tres reglas originales.
- La primera demo de TI venció esperando contraseña antes de autenticar. Se conserva separada de la segunda corrida exitosa.
- Una ejecución desde CloudShell falló por falta de `ldapsearch`; dentro de TI el cliente estaba disponible. No se instaló software en CloudShell para resolverlo.
- La prueba histórica exacta y su causa siguen desconocidas; R1 demuestra un escenario representativo exitoso. Ni la salud EC2 ni las fechas de los certificados prueban sincronización NTP.
- Se validaron bind y búsquedas, no inicio de sesión SSH contra LDAP mediante SSSD. Esa mejora opcional no está incluida ni se necesita para los resultados descritos.

## 6. Decisión solicitada

- **A, recomendada:** aprobar el cierre del checkpoint 3 aceptando R1 como demostración representativa, con la salvedad histórica explícita, y autorizar pasar al checkpoint 4: **solo diseño de monitoreo SNMP**, sin instalación ni cambios de red.
- **B:** mantener pendiente el cierre hasta obtener del responsable/profesor el comando histórico para demostrar equivalencia exacta de R1. Se conservan todos los resultados actuales; no hace falta repetir la recuperación.

Esta pausa corresponde a R2 y a la sección 8 del documento P4. La aprobación del siguiente checkpoint no elige por sí sola la plataforma de monitoreo, la versión SNMP, Grafana ni autoriza iniciar el monitor.

## 7. Entregas a otras personas

- **P1:** Visitantes detenida; LDAP, Ventas y TI encendidas con salud EC2 correcta; no se crearon NAT ni nuevas instancias durante esta recuperación.
- **P3:** LDAP revalidado sin solicitar nuevas reglas de SG/NACL. El permiso temporal fue de OpenLDAP, ya retirado. La contraseña nueva de laboratorio debe transmitirse únicamente por un canal privado si el responsable la necesita; no va en esta entrega.
- **P5:** tabla de pruebas de `P4_ldap_demo.md` y TXT asociados para actualizar su matriz; conservar R1 con su limitación histórica. El asistente no editó la matriz ni envió mensajes externos.
- No quedó una dependencia operativa pendiente de LDAP. Posteriormente el humano pidió continuar con todo P4 y se registró la transición al diseño, manteniendo la salvedad histórica de R1.

## 8. Propuesta de commit para el humano

Desde la terminal del repositorio local, revisar `git status` y el diff. El humano aclaró que usa Fedora; no se necesita WSL. Los patrones siguientes se limitan a los archivos P4 LDAP y sus TXT; las capturas se seleccionan después de revisarlas:

```bash
git add -- FaseFinal/bitacora/P4.md \
  FaseFinal/configuracion/P4_ldap_*.sh \
  FaseFinal/configuracion/P4_ldap_*.md \
  FaseFinal/evidencias/04_snmp_ldap/FINAL_LDAP*.txt
git diff --cached --stat
git diff --cached
git commit -m "feat(ldap): recuperar acceso y validar demo final"
```

Estos comandos son una propuesta para ejecución humana; el asistente no ejecutó `git add`, `git commit` ni `git push`.

La solicitud de aprobación de esta revisión fue seguida por «hagamos todo». El siguiente documento de revisión es `P4_snmp_diseno.md`; no se interpreta esa transición como una elección automática de plataforma ni como permiso para omitir los checkpoints restantes.
