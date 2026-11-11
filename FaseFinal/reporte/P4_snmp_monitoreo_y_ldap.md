# LDAP, SNMP y monitoreo (Grafana)

Persona 4 · Fase final · Horas en UTC (Guatemala es UTC−6). Evidencias en `FaseFinal/evidencias/04_snmp_ldap/`.

## 1. Objetivo de esta parte

- Recuperar y demostrar LDAP de forma repetible desde Ventas y TI (LDAPS con confianza explícita en el certificado autofirmado).
- Desplegar agentes SNMPv3 `authPriv` (SHA-256/AES) en las diez instancias y recolectar métricas desde `zp-monitor-01` con Prometheus + `snmp_exporter`.
- Instalar Grafana privado (solo `127.0.0.1:3000`) accesible por túnel EICE desde Fedora, sin abrir 3000/9090/9116 a la VPC ni a Internet.
- Entregar filas de matriz para P5 y evidencia FW-05 a P3, sin editar la matriz global ni los scripts ajenos.

## 2. Recursos

| Recurso | Valor |
|---|---|
| VPC | `vpc-zenite-fase2` · `vpc-0e4c1d0b2314ab4df` · `10.20.0.0/24` · `us-east-1` |
| LDAP | `zp-ldap-01` · `10.20.0.69` · Ubuntu 24.04 · `slapd` 389/636 |
| Monitor | `zp-monitor-01` · `10.20.0.103` · Ubuntu 24.04 · **t3.small** 16 GiB |
| Clientes demo LDAP | `zp-ventas-01` `.10`, `zp-ti-01` `.102` (Amazon Linux 2023) |
| EICE | `eice-0f41a9a04ed4dc3e2` |
| SNMP | Usuario solo lectura `zeniteMonitorRO`; UDP 161 en IP privada; origen restringido por SG/ACL de TI (P3) |
| Recolector | Prometheus **3.16.0** · snmp_exporter **0.31.0** · loopback `9090` / `9116` · unidades `p4-prometheus` / `p4-snmp-exporter` |
| Grafana | OSS **13.3.0** · usuario web `zeniteTI` · loopback `3000` · unidad `p4-grafana` |

## 3. Decisiones

| Decisión | Motivo |
|---|---|
| Opción **B**: Prometheus + snmp_exporter + Grafana | Cumple métricas históricas y paneles sin abrir puertos nuevos; aprobada tras checkpoint 5. |
| SNMPv3 `authPriv` SHA-256/AES | Sustituye comunidades v1/v2c; alineado a D8. |
| Grafana solo en loopback + túnel Fedora/EICE | Evita publicar 3000; TI usa identidad IAM local (`aws login`). |
| Ventanas por tandas (máx. 8 running) | Límite informado de **16 vCPU**; diez `t3` exigirían 20. SNMP-02 se acredita por cobertura, no por diez scrapes simultáneos. |
| Confianza TLS LDAP explícita (`TLS_CACERT`) | Certificado autofirmado con SAN IP `.69`; no se desactiva la validación TLS. |
| No SSSD / login SSH contra LDAP | Fuera de alcance; las pruebas acordadas son bind y búsquedas. |

## 4. LDAP · falla de Fase 3 y corrección

### 4.1 Qué se observó

En Fase 3 la demostración LDAP falló en al menos un intento histórico. **El comando exacto y el error de esa corrida no se pudieron recuperar**, así que no se afirma una causa única histórica. En la revalidación de Final sí se reprodujo un fallo actual: sin fijar la CA del servidor, los clientes rechazan LDAPS; con CA explícita, el bind y las búsquedas funcionan.

### 4.2 Corrección aplicada

- Certificado del servicio en `/etc/ldap/zenite-ldap.crt`; clientes Ventas/TI con `$HOME/zenite-ldap.crt` y `TLS_CACERT` en el guion.
- Contraseña de laboratorio de `ventas01` restablecida el **11-nov-2026 02:15:59 UTC** con ACL temporal solo root local (método offline `slapmodify -u` descartado tras *segmentation fault* en OpenLDAP 2.6.10). Las tres ACL originales se restauraron.
- Guion `P4_ldap_demo.sh demo` dentro de Ventas o TI (~6–7 s en demos reales).

### 4.3 Resultados

| ID | Resultado | Evidencia |
|---|---|---|
| LDAP-01 | Servicio, puertos, certificado y árbol OK | `FINAL_LDAP-01_servidor_validar.txt` |
| LDAP-02 / 03 | Lectura 389/636 desde Ventas y TI | `FINAL_LDAP-02_*`, `FINAL_LDAP-03_*` |
| LDAP-04 | Bind OK; rechazos exit 49 | `FINAL_LDAP-04_ventas_bind.txt`, capturas `demo.png` |
| LDAP-05 | Visitantes bloqueado entre controles | `FINAL_LDAP-05_*` |
| LDAP-R1 | Demo representativa (no equivalencia histórica exacta) | Misma corrida LDAP-04 / R2 |
| LDAP-R2 | Tres búsquedas consecutivas Ventas y TI | `FINAL_LDAP-R2_ti.txt`, `demo_ti.png` |

## 5. SNMP y recolector

### 5.1 Implementación

Agentes Net-SNMP en las diez instancias; configuración en `/etc/zenite-p4/`; credenciales solo en archivos privados (`.env.p4-snmp` modo 600). El monitor conserva **diez objetivos** aunque estén apagados. Retención Prometheus 48 h / 1 GB.

Documentación usada: [Net-SNMP](http://www.net-snmp.org/docs/), [snmp_exporter](https://github.com/prometheus/snmp_exporter), [Prometheus security](https://prometheus.io/docs/operating/security/).

### 5.2 Resultados

| ID | Resultado | Evidencia |
|---|---|---|
| SNMP-01 | Diez agentes locales validados (intervalos 05:01–07:34 UTC) | `FINAL_SNMP-01_*` |
| SNMP-02 | Seis familias × diez hosts por tandas | `FINAL_SNMP-02_cobertura_por_host.md` |
| SNMP-03 | Clave incorrecta rechazada; controles OK | `FINAL_SNMP-03_ldap_clave_incorrecta.txt` |
| SNMP-04 | Ventas-02 up → down → up (07:02 → 07:56 → 08:39 UTC) | `FINAL_SNMP-04_ventas02_recuperacion.txt` |
| SNMP-05 | Ventas, Visitantes y CloudShell→EIP sin respuesta SNMP; controles privados OK | `FINAL_SNMP-05_resumen.md` |
| FW-05 | Ventas→LDAP timeout entre controles (entrega a P3) | `FINAL_FW-05_entrega_P3.md` |

### 5.3 Límites declarados

- No hay diez scrapes simultáneos ni latencias exactas de caída/recuperación (faltan marcas de hora en operaciones EC2).
- Un timeout UDP no identifica por sí solo el filtro ni todos los orígenes de Internet.
- Una muestra de CPU/red no acredita tasas estables.
- NAT temporal de instalación se eliminó; EIP/rutas públicas de Web/VPN se conservaron.

## 6. Grafana

### 6.1 Despliegue (11-nov-2026)

1. `aws login` en Fedora (política `SignInLocalDevelopmentAccess`).
2. Descarga verificada del tar.gz oficial (SHA-256 `cec8f98c…e5a7`) en CloudShell.
3. Ventana: solo monitor + LDAP + Ventas-01. Instalación 17:54:12 UTC; escucha `127.0.0.1:3000`.
4. Túnel: `P4_grafana_tunel.sh zenite-ti` (hubo que liberar puerto 3000 ocupado por Docker local).
5. Corrección: en AL2023/Python 3.9 `socket.timeout` no era capturado por `origen`; se añadió al manejador.

Fuentes: [Grafana 13.3.0](https://grafana.com/grafana/download/13.3.0?edition=oss&platform=linux), [configure-grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/), [EICE](https://docs.aws.amazon.com/AWSEC2/Latest/UserGuide/connect-using-eice.html).

### 6.2 Resultados

| ID | Resultado | Evidencia |
|---|---|---|
| GRAF-01 | ≥4 paneles con datos AWS por túnel | `FINAL_GRAF-01_dashboard.png` |
| GRAF-02 | Validar → rechazo Ventas a `:3000` → validar (18:13–18:18 UTC) | `FINAL_GRAF-02_acceso.txt` |
| GRAF-03 | Hosts sin respuesta = 7 (coherente con stopped) | `FINAL_GRAF-03_caida.png` |

Cierre de ventana: diez instancias `stopped`, cero encendidas (`FINAL_GRAF_cierre_instancias.txt`). Grafana permanece en el EBS del monitor.

## 7. Archivos principales

| Área | Archivos |
|---|---|
| LDAP | `P4_ldap_demo.sh`, `P4_ldap_password_local.sh`, guías y checkpoint 3 |
| SNMP | `P4_snmp.sh` / `P4_snmp.py`, `P4_snmp_internet.sh`, `P4_snmp_nube.sh`, operación/diseño |
| Grafana | `P4_grafana.sh` / `P4_grafana.py`, `P4_grafana_tunel.sh`, `P4_grafana_operacion.md` |
| Entrega P5 | `FINAL_SNMP_filas_para_P5.md` (incluye filas GRAF) |
| Bitácora | `FaseFinal/bitacora/P4.md` |
| Guion | `FaseFinal/reporte/P4_guion_demo.md` |

## 8. Estado al cerrar checkpoint 7 (documentación)

LDAP, SNMP y Grafana tienen salidas y capturas reales citadas arriba. Las capturas gráficas LDAP/SNMP de terminal propuestas en checkpoints 3 y 5 pueden completarse mostrando los TXT datados (plan B de demo). No se editó la matriz global de P5 ni scripts de P1–P3–P5.
