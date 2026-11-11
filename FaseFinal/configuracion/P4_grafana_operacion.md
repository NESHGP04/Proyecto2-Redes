# Checkpoint 6 · Grafana privado

**Despliegue y pruebas GRAF-01/02/03 ejecutados el 11-nov-2026.** Grafana OSS 13.3.0 instalado en `zp-monitor-01` (127.0.0.1:3000). Ventana EC2: monitor + LDAP + Ventas-01. Túnel Fedora por EICE. Evidencias: `FINAL_GRAF-01_dashboard.png`, `FINAL_GRAF-02_acceso.txt`, `FINAL_GRAF-03_caida.png`. Corrección aplicada: `origen` captura también `socket.timeout` (Python 3.9/AL2023). NAT no recreado. Al cerrar la ventana: detener las tres instancias y conservar salida.

## Estado preparado y fuentes

Grafana OSS **13.3.0**, paquete oficial Linux amd64:

```text
grafana_13.3.0_40412481033_linux_amd64.tar.gz
SHA256 cec8f98cc59bc1a1945833b652371a073be678c5c159a9b1695ad63c04fae5a7
```

Se descargó y comprobó localmente contra [la publicación oficial](https://grafana.com/grafana/download/13.3.0?edition=oss&platform=linux). Aproximadamente 460 MiB. La instalación usa el binario independiente soportado por [Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/), sin instalar dependencias ni modificar repositorios del monitor. CloudShell descarga y copia por EICE; no requiere recrear NAT ni revertir ACL TI.

Archivos nuevos: `P4_grafana.sh`, `P4_grafana.py`, `P4_grafana_tunel.sh`, `P4_grafana_dashboard.json`, `P4_grafana.env.example`, esta guía y pruebas en `tests/P4_grafana_*`. El JSON es configuración pública reproducible, no evidencia de datos AWS. Para subir a CloudShell bastan los dos primeros; el módulo genera el dashboard/provisioning.

## 1. Ahora: preparar acceso local en Fedora

Abrir **Konsole o Terminal de Fedora**, fuera de CloudShell. Instalar cliente AWS y OpenSSH desde repositorios de Fedora:

```bash
sudo dnf install -y awscli2 openssh-clients
aws --version
aws login --profile zenite-ti --region us-east-1
```

El paquete se llama [awscli2 en Fedora](https://packages.fedoraproject.org/pkgs/awscli2/awscli2/). `aws login` requiere CLI >= 2.32 y abre el navegador para usar la identidad web; crea credenciales temporales locales. Elegir la identidad IAM autorizada de TI de la cuenta del proyecto. El nombre del perfil `zenite-ti` no concede permisos ni convierte otra identidad en TI. Si pide región, `us-east-1`.

Hace falta permiso **SignInLocalDevelopmentAccess** además de los permisos de EC2/EICE existentes. No se ha comprobado que la identidad lo tenga. Si aparece AccessDenied, conservar el nombre de la acción/error sin compartir URL/código/token y coordinar con el responsable IAM; no cambiar políticas ni usar root como solución automática. Fuente: [inicio de sesión AWS CLI con acceso web](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html).

Después de un inicio correcto, comprobar solo cuenta, sin imprimir ARN personal:

```bash
aws sts get-caller-identity --profile zenite-ti --region us-east-1 --query Account --output text
```

Esperado: `703461917799`. No pegar claves, archivos ~/.aws ni enlaces/códigos de inicio. Se espera la salida antes de encender servidores para la instalación; las instancias siguen detenidas según la última evidencia. La preparación del paquete siguiente puede hacerse en paralelo desde CloudShell.

## 2. Preparar el paquete desde el navegador, sin encender EC2

En **CloudShell → Actions → Upload file**, subir desde este repositorio `P4_grafana.sh` y `P4_grafana.py`. Son nombres nuevos. Si ya existen, conservarlos con otro nombre antes de volver a subir; no pegar prompts ni redirecciones de transcripciones.

```bash
bash "$HOME/P4_grafana.sh" descargar
```

Descarga a HOME y verifica SHA-256 antes de poner el nombre definitivo. Exige 600 MiB libres, no sobrescribe un paquete distinto y conserva/revalida uno correcto. Usa el módulo P4_snmp.py ya disponible, cuyo checksum se fija; no lo modifica ni rota secretos. No crea NAT, enciende instancias ni cambia AWS. Compartir solo su resultado público.

## 3. Ventana de instalación después de verificar acceso IAM local

Se necesitan solo **monitor, LDAP y Ventas-01** para datos reales y prueba de aislamiento; seis vCPU. Las tres están detenidas en la última tabla. P1 encender cambia su estado y genera cómputo durante la ventana; conserva IP/tipo/configuración.

Desde **CloudShell**, cuando el acceso local esté listo:

```bash
bash "$HOME/P1_instancias.sh" encender zp-monitor-01 zp-ldap-01 zp-ventas-01 &&
aws ec2 wait instance-status-ok --region us-east-1 --instance-ids i-00e786cb51a422c36 i-04f9cc2b9ee3f77cd i-0f3bd7b0615933e00 &&
aws ec2 wait system-status-ok --region us-east-1 --instance-ids i-00e786cb51a422c36 i-04f9cc2b9ee3f77cd i-0f3bd7b0615933e00
```

Copiar paquete público y scripts nuevos; no se copian claves SNMP:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 --copiar "$HOME/P4_grafana.sh" "$HOME/P4_grafana.py" "$HOME/grafana_13.3.0_40412481033_linux_amd64.tar.gz" &&
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_grafana.sh" preflight'
```

La copia de ~460 MiB puede tardar. Preflight verifica host/IP/Ubuntu/arquitectura, Prometheus/exporter existentes y privados, al menos 4 GiB libres/600 MiB de RAM, puerto 3000 libre y ausencia de Grafana previo. No cambia configuración. Recibir/revisar su salida antes de instalar.

## 4. Instalar solo Grafana dentro del monitor

Con preflight correcto, conectar desde **CloudShell**:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01
```

Dentro de **ubuntu@zp-monitor-01**, ejecutar:

```bash
sudo -n bash "$HOME/P4_grafana.sh" instalar --paquete "$HOME/grafana_13.3.0_40412481033_linux_amd64.tar.gz"
```

El plan concreto pide `si` y después contraseña nueva de laboratorio dos veces, oculta y sin plazo de 20 s. Usar 16–128 caracteres ASCII sin espacios y guardarla en gestor/.env local ignorado. Usuario `zeniteTI`; no se usa admin/admin.

Instala exclusivamente el usuario sin login `p4grafana`, `/usr/local/lib/zenite-p4-grafana`, `/etc/zenite-p4-grafana`, `/var/lib/zenite-p4-grafana` y `p4-grafana.service`. Binarios root, configuración root/grupo del servicio, contraseña/clave privada de Grafana 640 y datos privados del usuario. El archivo INI usa el proveedor `file`, no valores secretos versionados ni argumentos de comandos. SQLite se inicializa con esa contraseña la primera vez; repetir instalación no la rota ni reemplaza la base. Detecta configuración ajena o instalación parcial y se detiene.

Escucha **127.0.0.1:3000**, sin anónimos/autoregistro, plugins descargables ni comprobación de actualizaciones. Unidad sin root, sistema de archivos protegido y límite de memoria 768 MiB. No cambia snmpd, archivos/credenciales SNMP ni unidades/configuración de Prometheus. Ante fallo se solicita detener/deshabilitar solo Grafana, se comprueba si sigue activo y se conservan archivos parciales para revisar; no promete rollback de otros servicios ni recuperación automática ante SIGKILL/energía.

Fuentes: [configuración, http_addr y file provider](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/), [provisión de datasource/dashboard](https://grafana.com/docs/grafana/latest/administration/provisioning/).

```bash
sudo -n bash "$HOME/P4_grafana.sh" --validar
```

Comprueba hashes, servicio, loopback, salud SQLite/versión, rechazo anónimo, datasource local y dashboard provisionado; lista estados reales de Prometheus. No declara por sí solo PASS de GRAF-01/02/03.

## 5. Túnel desde Fedora y navegador local

Con Grafana validado, abrir **la terminal Fedora**, desde la raíz del repositorio:

```bash
bash FaseFinal/configuracion/P4_grafana_tunel.sh zenite-ti
```

Comprueba cuenta y monitor exactos, puerto local libre, crea una clave SSH temporal local, envía solo su pública con EC2 Instance Connect y usa OpenSSH `-L 127.0.0.1:3000:127.0.0.1:3000` mediante el endpoint existente/puerto 22. No copia la llave privada de CloudShell ni abre puertos AWS. Conserva known_hosts en archivo propio, acepta solo hosts nuevos y rechaza cambios. La clave temporal se elimina al cerrar. Ctrl+C termina el túnel; no apaga EC2. Los túneles EICE tienen duración limitada y pueden requerir volver a ejecutar.

En el navegador de esa misma Fedora:

```text
http://localhost:3000/d/zenite-snmp
```

Ingresar `zeniteTI` y contraseña de Grafana. Diez paneles: respuesta por host, recolector, CPU, RAM, tráfico recibido/enviado, raíz, uptime SNMP, cantidad sin respuesta y procesos. El selector conserva los diez hosts, incluidos apagados. Las tasas de red requieren varias muestras; no se rellena ausencia con cero. El uptime corresponde al agente. La disponibilidad SNMP no prueba por sí sola estado EC2; correlacionar con P1. Prometheus y exporter siguen en loopback 9090/9116.

Fuentes: [OpenTunnel AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/ec2-instance-connect/open-tunnel.html), [requisitos y permisos EICE](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html). Si se deniega una acción, conservar el error y coordinar IAM; no abrir 3000, 9090, 9116 ni SSH público.

## 6. Pruebas reales pendientes

- **GRAF-01:** cuatro o más paneles con datos AWS reales visibles por el túnel. Captura `FINAL_GRAF-01_dashboard.png`, con selección de hosts/hora y datos; evitar foto del formulario de contraseña. TXT de validación como complemento.
- **GRAF-02:** navegador autorizado TI por túnel, escucha loopback y timeout/rechazo desde Ventas, con controles positivos locales anterior/posterior. Copiar los dos scripts nuevos a Ventas, donde ya existen módulo SNMP/CSV:

```bash
bash "$HOME/P3_eice.sh" zp-ventas-01 --copiar "$HOME/P4_grafana.sh" "$HOME/P4_grafana.py" &&
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_grafana.sh" --validar' &&
bash "$HOME/P3_eice.sh" zp-ventas-01 'sudo -n bash "$HOME/P4_grafana.sh" origen' &&
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_grafana.sh" --validar'
```

Ese bloque se ejecuta en CloudShell; Ventas solo consulta TCP 3000, no instala servicios. Captura/transcripción `FINAL_GRAF-02_acceso`. El resultado aislado no cierra la prueba.

- **GRAF-03:** panel de hosts sin respuesta/estado rojo real y coherente con la tabla EC2 de siete instancias detenidas en esta ventana. No hace falta otro apagado para producirlo. Captura `FINAL_GRAF-03_caida.png`, distinguiendo parada intencional de incidente. No se inventan alertas enviadas por correo ni tiempos de detección.

Al terminar, cerrar túnel y detener explícitamente las tres instancias de la ventana usando P1. No crear/destruir NAT para este procedimiento. No se considera apagado sin salida real. Capturas y salidas AWS siguen pendientes hasta recibirlas; la prueba local con métricas sintéticas no las reemplaza.

## Pruebas locales

Trece regresiones del instalador: paquete distinto/enlaces, rutas/miembros peligrosos antes de extraer, raíz legítima, conflicto previo, arquitectura, estado parcial, cancelación/contraseña inválida antes de mutar, repetición, orígenes y configuración privada.

Cinco regresiones adicionales del túnel con AWS/SSH sustituidos: cuenta ajena, monitor apagado, perfil malicioso, reenvío loopback y eliminación de clave incluso al fallar SSH.

Integración real Grafana 13.3.0 + Prometheus 3.16.0 en Fedora 44 sin root ni puertos públicos: SQLite, contraseña sintética/file provider, rechazo anónimo, diez paneles provisionados y diez consultas a través de Grafana con datos sintéticos. Nueve targets up y uno down. La primera pasada encontró falta de Content-Type del servidor de métricas de prueba; se corrigió el fixture y se repitió correctamente. No era un resultado AWS ni fallo de SNMP desplegado.

```bash
python3 FaseFinal/configuracion/tests/P4_grafana_casos.py
python3 FaseFinal/configuracion/tests/P4_grafana_integracion_local.py --paquete /tmp/p4-grafana-build/grafana_13.3.0_40412481033_linux_amd64.tar.gz --prometheus /tmp/p4-snmp-build/prometheus-3.16.0.linux-amd64/prometheus
```

Estas integraciones no ejecutan systemd ni sustituyen la validación de unidad/usuario de servicio y navegador en EC2. Resumen en `FINAL_GRAF_pruebas_locales.txt`.
