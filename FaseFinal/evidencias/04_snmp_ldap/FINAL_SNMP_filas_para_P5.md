# Filas SNMP para revisión e incorporación por P5

Resultados propuestos a partir de las salidas reales recibidas; P4 no editó la matriz global. Horas UTC del 11-nov-2026. Las capturas gráficas aún necesitan aportarse/verificarse; los enlaces son transcripciones e índices de evidencia textual.

| ID | Esperado | Obtenido real | Estado propuesto | Evidencia |
|---|---|---|---|---|
| SNMP-01 | Agente activo y consulta v3 correcta en las diez instancias | Diez instalaciones/validaciones locales en sus respectivos intervalos, 05:01:43–07:34:20; escucha en IP privada, SHA-256/AES y usuario solo lectura. No diez agentes encendidos simultáneamente. | PASS por host en intervalos | Archivos FINAL_SNMP-01_*; [índice del cierre](../../configuracion/P4_snmp_checkpoint5.md) |
| SNMP-02 | Monitor obtiene disponibilidad, CPU, RAM, disco, interfaces y procesos de todos los hosts | Seis familias de los diez hosts recibidas por tandas; referencias completas para piloto/Ventas y secciones completas de otros cinco en fragmento de primera tanda. Ocho scrapes up por tanda, diez objetivos conservados. No se afirman diez scrapes simultáneos ni tasas estables con una sola muestra. | PASS de cobertura por tandas, para aceptación del equipo | [Cobertura 10 × 6](FINAL_SNMP-02_cobertura_por_host.md) |
| SNMP-03 | Credenciales incorrectas rechazadas desde origen permitido | Monitor → LDAP con clave incorrecta exit 1, controles válidos anterior/posterior correctos, 05:36:16 | PASS para autenticación contra LDAP | [Clave incorrecta](FINAL_SNMP-03_ldap_clave_incorrecta.txt) |
| SNMP-04 | Monitor observa pérdida de respuesta tras parada del cliente | Ventas-02 up 07:02:40; parada EC2 explícita y stopped posterior; scrape down 07:56:42. Tras inicio explícito/running, consulta autenticada exit 0 y scrape up 08:39:16. Sin medición de latencia por falta de horas exactas de parada/inicio. | PASS, incluida recuperación | [Cadena y recuperación](FINAL_SNMP-04_ventas02_recuperacion.txt) |
| SNMP-05 | Consultas SNMP desde Ventas, Visitantes e Internet sin respuesta | Ventas → LDAP timeout 08:02:33; Visitantes → LDAP timeout 08:29:27, ambos entre controles correctos del monitor. CloudShell exterior → EIP VPN/Web timeout 08:22:14/16, cuatro controles privados correctos con las mismas claves. Correlacionado con SG/ACL restringidos. | PASS en orígenes/destinos/intervalos probados | [Resumen de aislamiento](FINAL_SNMP-05_resumen.md) |

Para SNMP-02, el límite informado de 16 vCPU impidió diez t3 simultáneas; se documentaron tandas y dos errores de inicio sin ocultarlos. P5/equipo deben conservar esta limitación al incorporar el resultado. Requerir diez simultáneas implica otra decisión de capacidad; no se solicitó un aumento ni se cambiaron tipos.

Para SNMP-05, el timeout UDP no identifica el equipo que descarta ni todos los orígenes de Internet; los controles y reglas revisadas son parte de la evidencia. No se usó clave errónea como prueba de bloqueo de red.

FW-05 corresponde a P3: [entrega preparada](FINAL_FW-05_entrega_P3.md).

| ID | Esperado | Obtenido real | Estado propuesto | Evidencia |
|---|---|---|---|---|
| GRAF-01 | Dashboard con datos reales vía acceso autorizado | Túnel Fedora → Grafana; ≥4 paneles con series AWS (respuesta, recolector, CPU, RAM, tráfico); 3 hosts up / 7 down | PASS | [Dashboard](FINAL_GRAF-01_dashboard.png) |
| GRAF-02 | Acceso TI; Grafana no alcanzable desde Ventas | Validar monitor 18:13:29 → Ventas timeout/OBSERVADO a :3000 18:13:40 → validar monitor 18:18:33; escucha solo loopback | PASS | [Acceso y rechazo](FINAL_GRAF-02_acceso.txt) |
| GRAF-03 | Estado de hosts sin respuesta visible | Panel Hosts sin respuesta SNMP = 7, coherente con siete stopped de la ventana | PASS | [Caída](FINAL_GRAF-03_caida.png) |
