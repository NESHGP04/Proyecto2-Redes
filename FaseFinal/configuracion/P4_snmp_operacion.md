# Checkpoint 5 · Instalar y comprobar SNMPv3

**Estado: checkpoint 5 aprobado por el humano con «continua».** Cierre concreto: [P4_snmp_checkpoint5.md](P4_snmp_checkpoint5.md). Grafana todavía no se ha iniciado.

Diez agentes SNMPv3 instalados y seis familias de métricas recibidas de todos por tandas. Ventas-02 completó up → parada/stopped → down → inicio/running → up; control autenticado y scrape up a las 08:39:16 UTC / 02:39:16 Guatemala del 11-nov-2026. La ausencia del temporal del rescate quedó comprobada a las 08:39:37 UTC / 02:39:37 Guatemala. Ocho scrapes up; Visitantes y VPN down, coherentes con sus paradas explícitas. Filas listas para P5 en `FINAL_SNMP_filas_para_P5.md`, con límites de cobertura por tandas y pruebas de origen.

TI restaurada, NAT temporal eliminado y EIP temporal liberada; Web/VPN mantienen sus excepciones previstas. La limpieza del guion exterior también quedó confirmada. **Apagado posterior acreditado por salida P1: diez instancias stopped, cero encendidas**, sin hora propia visible. Evidencia `FINAL_SNMP_cierre_instancias.txt`. La aprobación ya fue recibida; el procedimiento actual es [P4_grafana_operacion.md](P4_grafana_operacion.md), inicialmente con Fedora/CloudShell y EC2 todavía detenido.

Esta guía conserva procedimientos e incidentes del despliegue; las secciones históricas no deben repetirse como una instalación nueva. CloudShell administra servidores, la futura terminal Fedora mantendrá el túnel y el navegador local mostrará Grafana. No se abren 3000, 9090 ni 9116 en AWS.

**Incidente de archivos vacíos:** Intranet quedó instalado y validado tras corregir sus archivos. No se recibió salida pública completa del rescate; no se reconstruyen sus backups/pasos. La ausencia de su archivo temporal sí está acreditada por lectura posterior. Se conserva abajo el procedimiento histórico, no una tarea pendiente ni un paso habitual.

### Rescatar archivos vacíos de CloudShell

Salir de Intranet con `exit`. En **CloudShell → Actions → Upload file**, subir `P4_recuperar_archivos_cloudshell.sh` de este repositorio, con su nombre propio (no reemplaza P4_snmp.py). En CloudShell:

```bash
bash "$HOME/P4_recuperar_archivos_cloudshell.sh"
```

El plan pide `si` antes de restaurar. Verifica el checksum de P4_snmp.py de la versión revisada, conserva originales bajo un directorio privado y repone el wrapper y CSV solo si estaban vacíos o coinciden con el contenido previsto. Toma las mismas credenciales desde el archivo de servicio root/600 del monitor, mediante una copia temporal privada del usuario ubuntu y transporte EICE; valida el contenido sin imprimirlo. Si hay credenciales locales no vacías y distintas, conserva el estado y falla. Elimina las copias temporales local/remota y recopia los cuatro archivos a Intranet. Mantiene credenciales canónicas CloudShell en modo 600 y directorio 700; no instala servicios ni cambia reglas, tipos o claves.

Compartir solo la salida pública del rescate, no `transporte-privado.txt`, respaldos ni archivos de credenciales. Si falla transporte, conserva el diagnóstico privado; si no confirma limpieza remota lo informa expresamente. Ocho casos locales con transporte simulado cubren restauración, archivos distintos, claves distintas, descarga parcial, copia fallida, cancelación, código alterado y repetición.

El instalador real de Intranet ya respondió y validó v3 a las 06:24:23 UTC. Esto acredita sus archivos utilizables y su agente, pero no todos los pasos del rescate cuya salida no se recibió. Evidencia `FINAL_SNMP-01_intranet_agente.txt`. El comando vacío anterior queda conservado como intento sin instalación acreditada.

**Nota histórica de capacidad tras el error de cuota:** el inventario previo al lote confirmó cuatro running y seis stopped. Se eligieron dos tandas, con máximo previsto de ocho instancias encendidas (16 vCPU). TI, Ventas-02, NTP, Intranet y Visitantes ya se instalaron en la primera. El siguiente paso es consultar los ocho hosts desde monitor. Web y VPN siguen reservados para la segunda tanda; no repetir el encendido completo.

**Estado al cerrar la ventana de instalación (histórico):** diez agentes locales comprobados y ACL TI `acl-0d435e6e99660f33f` restaurada. NAT `nat-0c06dfd843c771516` eliminado y EIP temporal `eipalloc-0d4b2f085e3786e66` liberada; costo/resumen confirma NAT 0, dos EIP asociadas y ninguna sin asociar. Se conservan fallas heredadas de validación como tales. La siguiente consulta real al monitor comprobará EICE y SNMP después del cierre, junto con métricas Web/VPN. No repetir restauración ni destrucción.

## 1. Archivos y primera acción: solo lectura

En AWS, región **N. Virginia / us-east-1**, abre **CloudShell**. En **Actions → Upload file**, selecciona desde tu repositorio en Fedora estos archivos de `FaseFinal/configuracion/`:

1. `P4_snmp_nube.sh`
2. `P4_snmp.py`
3. `P4_snmp_objetivos.csv`

Quedan juntos en `$HOME` de CloudShell. No se sube `.env` ni se necesitan contraseñas para este paso. Ejecuta:

```bash
bash "$HOME/P4_snmp_nube.sh" --validar
```

Consulta las diez instancias por nombre, sus IP/SG, miembros del SG TI, reglas UDP 161 y retornos ACL, rutas, NAT, EICE y disco del monitor. Solo llama APIs `describe-*`; no enciende ni configura nada. Guarda JSON y `resultado.txt` bajo `~/final-config/P4_snmp_nube_<hora>_<aleatorio>/`.

**Comparte la salida pública antes de ejecutar la ventana siguiente.** Una regla amplia, otra IP, SG adicional o recurso duplicado hace fallar el diagnóstico sin cambiar AWS. `stopped` es información de inventario, no fallo del agente. Un `[OK]` de este guion no certifica que SNMP ya funcione.

Los archivos JSON permiten revisar la ACL original antes de una reversión: si contiene reglas adicionales a la política de P3, no utilizar el procedimiento estándar de recreación sin revisar cómo conservarlas.

La primera ejecución real ya fue recibida: 11-nov-2026 03:43:32–03:43:41 UTC / 10-nov 21:43:32–21:43:41 Guatemala. SG y retornos SNMP correctos; monitor detenido, `t3.small`, EBS 16 GiB, NAT ausente y ruta interna sin salida por defecto. Evidencia `FINAL_SNMP-DIAG_nube_20261111T034332Z.txt`. Aún falta ver la política completa de TI antes de la reversión. En **CloudShell**, el siguiente bloque muestra solo ACL TI/predeterminada del JSON ya guardado; no cambia AWS:

```bash
python3 - <<'PY'
import json
from pathlib import Path
folder = Path.home() / 'final-config/P4_snmp_nube_20261111T034332Z_ixzidd2l'
inventory = json.loads((folder / 'describe-instances.json').read_text())
hosts = [i for r in inventory['Reservations'] for i in r['Instances']]
monitor = next(i for i in hosts if any(t['Key'] == 'Name' and t['Value'] == 'zp-monitor-01' for t in i.get('Tags', [])))
acls = json.loads((folder / 'describe-network-acls.json').read_text())['NetworkAcls']
for acl in acls:
    if acl.get('IsDefault') or any(a['SubnetId'] == monitor['SubnetId'] for a in acl.get('Associations', [])):
        print(json.dumps(acl, indent=2))
PY
```

La ruta corresponde exactamente a esta corrida. No se asigna un estado más reciente al snapshot; si otra persona cambió la ACL después, repetir la consulta de solo lectura antes de usarla como base de la ventana.

El humano ya compartió ambas políticas completas. Las cinco reglas explícitas de `acl-zenite-ti` coinciden con `ACL_TI` de `P5_acls.sh`; solo está asociada a la subred TI y no contiene extras en el respaldo recibido. La ACL predeterminada permite todo en ambas direcciones. La evidencia normalizada está en `FINAL_SNMP-DIAG_acl_ti_preventana.json`. La lista de archivos muestra que faltan en CloudShell `P5_acls.sh`, `P1_dmz_infra.sh` y `P1_costos.sh`; `P1_gateways.sh` existe, pero su contenido no se ha comparado aún.

### Preparar el piloto antes de abrir la ventana NAT

Para no consumir una sesión NAT esperando archivos o resolviendo conflictos de paquetes, subir ahora los tres faltantes y los dos wrappers P4:

| Archivo | Ubicación en el repositorio |
|---|---|
| `P5_acls.sh` | `Fase3/configuracion/` |
| `P1_dmz_infra.sh` | `FaseFinal/configuracion/` |
| `P1_costos.sh` | `FaseFinal/configuracion/` |
| `P4_snmp.sh` | `FaseFinal/configuracion/` |
| `P4_monitor_snmp.sh` | `FaseFinal/configuracion/` |

Los archivos P1/P5 se suben tal como están; no se modifican. En **CloudShell**, comprobar que el script de NAT ya presente coincide con la versión revisada del repositorio:

```bash
printf '%s  %s\n' 'cb673fd865399b6d42a0fc6c745bd42a53e515012b14d25d21fc7fa668b61fe1' "$HOME/P1_gateways.sh" | sha256sum --check
```

Debe mostrar `OK`. Si no coincide, conservar la copia actual y revisar la diferencia antes de crear NAT; igual tamaño no demuestra igual contenido.

El siguiente cambio inicia únicamente el monitor existente para verificar SO, paquetes y espacio; no crea NAT ni modifica ACL:

```bash
bash "$HOME/P1_instancias.sh" encender zp-monitor-01
```

Esperar controles de estado y disponibilidad de EICE. LDAP ya figura encendido en el diagnóstico. En **CloudShell**, copiar solo archivos públicos y ejecutar preflight remoto de ambos nodos:

```bash
for p4_host in zp-monitor-01 zp-ldap-01; do
  bash "$HOME/P3_eice.sh" "$p4_host" --copiar \
    "$HOME/P4_snmp.sh" "$HOME/P4_monitor_snmp.sh" \
    "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv" || break
  bash "$HOME/P3_eice.sh" "$p4_host" \
    'sudo -n bash "$HOME/P4_snmp.sh" preflight' || break
done
```

Este preflight no instala paquetes, no solicita claves y no cambia servicios. Informa si Net-SNMP ya está instalado y el espacio libre; un paquete previo necesita revisión antes de aplicar el instalador. Compartir su salida antes de iniciar la ventana de la sección 2. Encender el monitor tiene costo de instancia; ya forma parte del piloto aprobado. No se redimensiona ni se arranca el resto del inventario con este paso.

El piloto ya se recibió: monitor en ejecución y preflight correcto a las 11-nov-2026 04:32:42 UTC / 10-nov 22:32:42 Guatemala, con 12699 MiB libres; LDAP a las 04:32:55 UTC / 22:32:55 Guatemala, con 4482 MiB. Ambos son Ubuntu y no tienen el paquete SNMP. El hash de `P1_gateways.sh` coincidió. Evidencia `FINAL_SNMP-DIAG_piloto_preflight.txt`. No repetir el encendido ni la copia pública para continuar. Los tres scripts de restauración/cierre aún faltan según el último listado recibido.

## 2. Preparación de la ventana, después del inventario revisado

Sube también `P4_snmp.sh` y `P4_monitor_snmp.sh` desde `FaseFinal/configuracion/`. Para operaciones AWS reutiliza sin modificar los scripts existentes `P1_instancias.sh`, `P1_gateways.sh`, `P5_acls.sh`, `P1_dmz_infra.sh`, `P1_costos.sh` y `P3_eice.sh`. Si falta alguno, subirlo desde su carpeta de Fase3/FaseFinal; no confundir sus nombres o versiones. No modificar archivos ajenos para eliminar sus comprobaciones.

Avisar al equipo con la anticipación del calendario de P1 y confirmar que nadie está usando la misma ventana NAT o cambiando ACL. El NAT y las instancias tienen costo; revisar el presupuesto actual con el responsable. Los precios históricos de los documentos no se presentan como cotización actual.

### Alcance concreto del NAT

`P1_gateways.sh crear` crea o reutiliza el NAT del proyecto y su EIP temporal, y configura la salida de la tabla interna. El código revisado no cambia la ruta actual de DMZ, aunque su validación antigua puede advertirla. No ejecutar este paso si el inventario muestra una ruta interna o NAT de otra sesión sin coordinación.

En **CloudShell**, cuando el alcance haya sido revisado y el equipo esté avisado, el siguiente bloque exige los tres archivos de restauración/cierre, prepara o conserva las claves privadas y solo después permite iniciar NAT:

```bash
if [[ -r "$HOME/P5_acls.sh" && -r "$HOME/P1_dmz_infra.sh" && -r "$HOME/P1_costos.sh" ]]; then
  bash "$HOME/P4_snmp.sh" credenciales &&
    bash "$HOME/P1_gateways.sh" crear
else
  echo '[FALLA] Faltan scripts de restauración/cierre. Sube los tres antes de crear NAT.' >&2
  false
fi
```

El primer `si`, si no hay claves previas, autoriza generarlas de forma privada (sección 3); el segundo confirma el plan de P1 para NAT/EIP temporal y salida interna con costo. Si la preparación privada falla, no se ejecuta el creador. No se muestra el contenido de las claves.

La validación heredada de Fase3 puede terminar con fallos por la ruta DMZ y el número de EIP, conocidos en `P1_calendario_nat.md`; no concluir que la creación no ocurrió ni repetirla ciegamente. Compartir la salida completa para confirmar el estado del NAT antes de revertir TI. Para interpretar esos avisos se revisan las salidas y se usa el validador de P1 de FaseFinal. Ante otro fallo, conservar la salida y detener la secuencia.

**NAT abierto confirmado:** el humano generó las claves a las 11-nov-2026 04:43:47 UTC y creó `nat-0c06dfd843c771516`, disponible con ruta interna activa en la validación de las 04:46:18 UTC (10-nov 22:46:18 Guatemala). La única falla recibida exige DMZ sin ruta por defecto, expectativa histórica que no aplica a la web pública de FaseFinal. Se conserva la ruta DMZ al IGW y no se vuelve a crear NAT para corregir ese aviso. Evidencia `FINAL_SNMP-DIAG_ventana_nat_abierta.txt`; la primera preparación abortada con Ctrl+C también se conserva. El contenido de las claves no se recibió ni se guarda aquí.

### Alcance concreto de la ACL TI

El mecanismo existente `P5_acls.sh --revertir ti` **reasocia TI a la ACL predeterminada y elimina su ACL dedicada**; no es una apertura selectiva de HTTPS. Durante esa ventana se relajan sus restricciones ACL y los SG se mantienen. Se usa solo si el inventario demuestra la política estándar restaurable, el equipo confirma la ventana y el humano acepta ese alcance al ejecutar el comando. Si hay reglas adicionales o se requiere una excepción menor, P3 debe preparar el cambio específico; no lo improvisa P4.

En **CloudShell**, después de esa revisión:

```bash
bash "$HOME/P5_acls.sh" --revertir ti
```

Confirmar `si` solo tras leer el alcance. **No usar `todo`**. Al terminar la instalación se recreará y asociará TI con `aplicar ti`, se validará y se probará de nuevo EICE. Si la salida no corresponde a TI, cancelar.

Después de recibir `Reversion completa.`, copiar solo las credenciales privadas de transporte al monitor y abrir su sesión. Esta transferencia no instala servicios. La copia de CloudShell se conserva; el instalador elimina la copia remota al completar correctamente:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 --copiar "$HOME/.config/zenite-p4/.env.p4-snmp"
bash "$HOME/P3_eice.sh" zp-monitor-01
```

La reversión TI y la copia privada ya fueron confirmadas por el humano; EICE siguió funcionando. Evidencia `FINAL_SNMP-DIAG_ti_temporal_y_eice.txt`. El prompt actual es `ubuntu@zp-monitor-01`: no repetir allí los comandos de `P3_eice.sh`, que pertenecen a CloudShell y por eso no existen en `/home/ubuntu`. La copia `.env.p4-snmp` ya llegó correctamente. La salida HTTPS y la instalación siguen pendientes.

Ya en **`ubuntu@zp-monitor-01`**, comprobar primero salida HTTPS con certificado verificado, sin instalar paquetes:

```bash
python3 - <<'PY'
import urllib.request
urls = [
    'https://archive.ubuntu.com/ubuntu/',
    'https://github.com/prometheus/snmp_exporter/releases/download/v0.31.0/sha256sums.txt',
]
for url in urls:
    with urllib.request.urlopen(url, timeout=15) as response:
        print('HTTPS OK', response.status, url)
PY
```

Si ambas devuelven `HTTPS OK 200`, el piloto puede ejecutar el instalador del agente de la sección 4. Si hay error de red, DNS o certificado, conservar la salida y resolverlo antes de intentar una instalación que dejaría una marca parcial. Esta conexión por EICE sirve también para comprobar que el acceso administrativo continúa después del cambio de ACL.

## 3. Credenciales privadas compartidas para los agentes

En **CloudShell**:

```bash
bash "$HOME/P4_snmp.sh" credenciales
```

Pide confirmación y genera dos claves distintas, aleatorias, sin imprimirlas, en `~/.config/zenite-p4/.env.p4-snmp` (directorio 700, archivo 600). Si existe, lo valida y conserva; no rota claves automáticamente.

Estas son claves de laboratorio para SNMP, diferentes de LDAP y AWS. Conserva una copia privada local conforme a la política `.env` del proyecto. Si usas **Actions → Download file** para guardarla en Fedora, selecciona exactamente ese archivo privado, ajusta sus permisos a 600 y guárdalo fuera de carpetas compartidas o dentro de un `.env` ignorado por Git. No lo pegues en el chat, historial, capturas o repositorio. La plantilla pública `P4_snmp.env.example` no contiene claves.

## 4. Piloto: monitor y LDAP

Propuesta de piloto: monitor y servidor LDAP que ya fue validado. Instalar SNMP administra únicamente `snmpd`; no modifica ni reinicia `slapd`. Un Net-SNMP previo sin marca P4 es conflicto: se revisa, no se reemplaza automáticamente.

Después de revisar el inventario y la ventana, en **CloudShell** enciende el monitor mediante P1:

```bash
bash "$HOME/P1_instancias.sh" encender zp-monitor-01
```

Espera sus controles de estado. LDAP debe seguir encendido. Copia los archivos públicos y la copia privada de transporte a ambos hosts:

```bash
for p4_host in zp-monitor-01 zp-ldap-01; do
  bash "$HOME/P3_eice.sh" "$p4_host" --copiar \
    "$HOME/P4_snmp.sh" "$HOME/P4_monitor_snmp.sh" \
    "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv"
  bash "$HOME/P3_eice.sh" "$p4_host" --copiar \
    "$HOME/.config/zenite-p4/.env.p4-snmp"
done
```

La copia privada se llama `.env.p4-snmp` en el home remoto; no sobrescribe `.env`. Antes de copiar, comprobar que no exista otra copia distinta de una ejecución anterior. El original privado de CloudShell se conserva. Después de una instalación correcta se elimina la copia remota de transporte y queda `/etc/zenite-p4/snmp.env`, root/600. No copiar una carpeta completa del repositorio, ya que puede contener secretos ignorados.

En **CloudShell**, puedes ejecutar el preflight remoto de solo lectura:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_snmp.sh" preflight'
bash "$HOME/P3_eice.sh" zp-ldap-01 'sudo -n bash "$HOME/P4_snmp.sh" preflight'
```

Para instalar, abre una sesión interactiva por host. Por ejemplo:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01
```

Ya en **`ubuntu@zp-monitor-01`**:

```bash
sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"
```

Explica y pide `si` antes de instalar paquetes, configurar la escucha privada, crear el usuario USM y comprobar autenticación. Usa SHA-256/AES con vista de solo lectura y sin comunidades v1/v2c. El servicio se enmascara temporalmente durante la instalación del paquete para impedir un arranque con configuración predeterminada. Guarda respaldo privado y hace rollback de sus archivos si falla la autenticación; el paquete instalado se conserva, y un intento parcial requiere revisión antes de reintentar.

Escribe `exit` para volver a CloudShell; conecta a `zp-ldap-01` y ejecuta el mismo comando dentro de esa instancia como `ubuntu`. En Amazon Linux el usuario SSH será `ec2-user`. El CSV, hostname, IP y SO se comprueban antes de cambiar nada.

Para validar un agente ya configurado, dentro de su instancia:

```bash
sudo -n bash "$HOME/P4_snmp.sh" --validar
```

Este modo lee configuración/estado y hace una consulta; no reinstala ni reinicia servicios. Guarda un registro nuevo. Un proceso principal previsto ausente es un fallo que se investiga, no motivo para iniciar otro servicio desde el instalador SNMP.

## 5. Recolector y Prometheus, dentro del monitor

El piloto real ya tiene agentes comprobados en monitor y LDAP, y un `snmpwalk` autenticado desde monitor a LDAP con exit 0. Evidencia: `FINAL_SNMP-01_ldap_y_control_monitor.txt`. Esa consulta de system no acredita todavía CPU, RAM, disco, interfaces ni procesos.

Primero comprobar las seis familias de ambos agentes. En **`ubuntu@zp-monitor-01`**:

```bash
sudo -n bash "$HOME/P4_snmp.sh" recolectar --host zp-monitor-01 --host zp-ldap-01
```

Si termina sin fallas, instalar el recolector en esa misma sesión:

```bash
sudo -n bash "$HOME/P4_monitor_snmp.sh" instalar
```

Instala dependencias de Ubuntu y descarga releases oficiales fijadas: **Prometheus 3.16.0** y **snmp_exporter 0.31.0**. Verifica SHA-256 contra el manifiesto oficial de cada release, crea usuario de servicio sin login y arranca unidades `p4-prometheus` y `p4-snmp-exporter`. Requiere 4 GiB libres de espacio antes de comenzar. Ambos servicios escuchan en loopback; se aplica retención 48 h / 1 GB de bloques, con espacio adicional para WAL/compactación.

La configuración del exporter se deriva de módulos oficiales de su misma release. Añade módulos acotados de uptime, procesos y disco raíz. Sus campos secretos se expanden desde el archivo de entorno privado leído por systemd; no se pasan claves en argumentos ni se escriben en YAML público. Se usa YAML para conservar claves enteras de enums de los módulos oficiales.

No instala Grafana en este checkpoint. Los diez objetivos se conservan en Prometheus aunque algunos estén apagados. El validador muestra `up/down/unknown` de cada scrape sin convertirlo automáticamente en estado EC2.

```bash
sudo -n bash "$HOME/P4_monitor_snmp.sh" --validar
sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ldap-01
sudo -n bash "$HOME/P4_snmp.sh" recolectar --host zp-ldap-01
```

El control usa `snmpwalk` autenticado. La recolección incluye uptime, CPU, RAM, disco raíz, interfaces y procesos declarados. CPU se obtiene de contadores UCD de Net-SNMP, conservando HR cuando esté disponible. RAM se identifica por tipo en `hrStorage`; el disco raíz declarado se obtiene de `dskTable` con `disk /`. Las tasas CPU/red necesitan al menos dos muestras; una colección inicial de contadores no demuestra una tasa estable.

Si el piloto falla, conservar su salida y corregir antes de distribuir al resto. No marcar SNMP-02 global por un piloto exitoso.

### Recuperar el fallo de extracción observado en el piloto

La salida real posterior informó ambos servicios `inactive`, ausencia de `/usr/local/lib/zenite-p4` y de ambas unidades, directorios de configuración/estado root:p4monitor y datos p4monitor:p4monitor. No se recibió listado del contenido del directorio de datos ni ficha del usuario: el modo de recuperación los verifica antes de cambiar nada.

Desde la sesión del monitor, `exit` para regresar a CloudShell. Subir por **Actions → Upload file** la versión corregida de `P4_snmp.py` de este repositorio, conservando el nombre. En **CloudShell**:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 --copiar "$HOME/P4_snmp.py"
bash "$HOME/P3_eice.sh" zp-monitor-01
```

Dentro de **`ubuntu@zp-monitor-01`**:

```bash
sudo -n bash "$HOME/P4_monitor_snmp.sh" recuperar-descarga \
  --registro-fallido /root/final-config/P4_snmp_zp-monitor-01_20261111T051132Z_fanx09ls/resultado.txt
```

Este modo solo admite el fallo de extracción revisado: registro original y marca privados coherentes, agente validado, mismas credenciales, usuario de sistema sin procesos, directorio de datos vacío, archivos esperados y ausencia de binarios/unidades. Si falta alguna condición, termina antes de confirmar o cambiar el estado parcial.

Tras escribir `si`, archiva la marca anterior en el nuevo registro privado como `monitor.failed.previo`, mantiene el registro original y reutiliza usuario/directorio vacío. Reintenta la instalación corregida con las mismas versiones, checksum y escucha loopback. No borra ni reinicia el agente snmpd. Si vuelve a fallar, conserva una nueva marca y el diagnóstico; no se declara recuperación completa. Este modo no admite otros fallos ni una instalación con datos.

La recuperación anterior **ya terminó correctamente** en la ejecución real recibida; no repetirla. El siguiente `--validar` consulta el estado después de un primer intervalo de scrape, sin reinstalar. `unknown` de arranque indica que todavía no hay una primera muestra; `down` posterior requiere revisar agente/red y no acredita por sí solo apagado de EC2.

## 6. Completar los diez agentes por tandas

El encendido completo recibió `VcpuLimitExceeded`: cuota regional de 16 vCPU. Las diez t3 previstas requieren 20 vCPU. Fuentes: [tipos T3](https://aws.amazon.com/ec2/instance-types/t3/) y [cuotas On-Demand](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-on-demand-instances.html).

El inventario regional posterior compartido por el humano muestra cuatro running (Ventas-01, TI, LDAP, monitor) y seis stopped (Ventas-02, Visitantes, NTP, Intranet, web, VPN). La tabla no incluye hora propia. Son las diez instancias previstas, sin otras filas de consumo en la salida recibida. El lote completo queda sustituido por tandas; no ejecutar el encendido de las seis juntas.

El piloto de Ubuntu y Amazon Linux ya está comprobado: tres agentes activos, seis familias en cada uno, raíz EBS de Ventas recibida y SNMP-03 LDAP correcto a las 05:36:16 UTC. La muestra anterior de Prometheus tenía monitor/LDAP up. Evidencias `FINAL_SNMP-02_ventas_metricas.txt` y `FINAL_SNMP-03_ldap_clave_incorrecta.txt`.

### Primera tanda: ocho instancias encendidas como máximo

**Avance real recibido:** TI y Ventas-02 ya quedaron correctos. NTP recibió sus archivos y llegó a confirmación, pero no recibió `si` antes de la interrupción a los 120 s. El código confirma antes de instalar paquetes; NTP no está acreditado como instalado. Intranet y Visitantes no se alcanzaron. El bucle siguiente queda como referencia de lo ya intentado; continuar con pasos individuales, sin repetir todo el lote.

En **CloudShell**, copiar únicamente el comando del recuadro, sin `~ $`, `>` ni salidas anteriores:

```bash
bash "$HOME/P3_eice.sh" zp-ntp-01
```

Dentro de **`ec2-user@zp-ntp-01`**, con los archivos ya copiados:

```bash
sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"
```

Escribir `si` y pulsar Enter cuando aparezca la pregunta; el plazo del guion es 120 s. La confirmación protege cada cambio del servicio. Si vuelve a interrumpirse, conservar la salida y revisar antes de continuar; no borrar marcas ni respaldos. Después se presentarán los pasos individuales para Intranet/Visitantes.

El reintento individual de NTP **ya terminó correctamente** a las 05:59:05 UTC; no repetirlo. Evidencia `FINAL_SNMP-01_ntp_agente.txt`. Salir de NTP con `exit`; en CloudShell copiar los archivos a Intranet y conectar:

```bash
bash "$HOME/P3_eice.sh" zp-intranet-01 --copiar "$HOME/P4_snmp.sh" "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv" "$HOME/.config/zenite-p4/.env.p4-snmp"
bash "$HOME/P3_eice.sh" zp-intranet-01
```

Dentro de **`ec2-user@zp-intranet-01`**, comprobar entorno y, si pasa, instalar solo snmpd:

```bash
sudo -n bash "$HOME/P4_snmp.sh" preflight && sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"
```

El primer intento de Intranet recibió tres archivos vacíos y no produjo salida del instalador. El reintento posterior ya terminó correctamente a las 06:24:23 UTC; no repetirlo. Desde Intranet, `exit` para regresar a CloudShell. Copiar los archivos recuperados a Visitantes y conectar:

```bash
bash "$HOME/P3_eice.sh" zp-visitantes-01 --copiar "$HOME/P4_snmp.sh" "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv" "$HOME/.config/zenite-p4/.env.p4-snmp"
bash "$HOME/P3_eice.sh" zp-visitantes-01
```

Dentro de **`ec2-user@zp-visitantes-01`**, ejecutar:

```bash
sudo -n bash "$HOME/P4_snmp.sh" preflight && sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"
```

Confirmar con `si` antes de 120 s. Este paso administra solo snmpd y usa las mismas claves; no cambia la ACL de Visitantes ni sus reglas. La instalación real de Visitantes ya terminó correctamente a las 06:28:06 UTC; evidencia `FINAL_SNMP-01_visitantes_agente.txt`. No repetirla.

En **CloudShell**, iniciar solo estas cuatro, que estaban detenidas en el inventario recibido. Con las cuatro ya encendidas, la capacidad prevista será 16 vCPU. El encendido genera costo de ejecución; no crea instancias, cambia tipos ni modifica rutas/EIP.

```bash
bash "$HOME/P1_instancias.sh" encender \
  zp-ventas-02 zp-ntp-01 zp-intranet-01 zp-visitantes-01
```

Después, instalar en esos cuatro destinos y en TI, que ya estaba encendido. El bloque busca ID único por nombre en la VPC verificada, espera controles de sistema/instancia, copia tres archivos públicos y las credenciales privadas existentes, y ejecuta preflight/instalación por EICE. Mantiene TTY para la confirmación `si` de cada agente. Ejecutar directamente en CloudShell, sin tuberías. Se detiene ante el primer fallo y no informa éxito global por terminar el bucle.

```bash
for p4_host in zp-ti-01 zp-ventas-02 zp-ntp-01 zp-intranet-01 zp-visitantes-01; do
  p4_iid=$(aws ec2 describe-instances --region us-east-1 \
    --filters "Name=vpc-id,Values=vpc-0e4c1d0b2314ab4df" \
      "Name=tag:Name,Values=$p4_host" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text) || break
  [[ "$p4_iid" =~ ^i-[0-9a-f]+$ ]] || { echo "[FALLA] Instancia no única o sin arrancar: $p4_host"; break; }
  aws ec2 wait instance-status-ok --region us-east-1 --instance-ids "$p4_iid" || break
  aws ec2 wait system-status-ok --region us-east-1 --instance-ids "$p4_iid" || break
  bash "$HOME/P3_eice.sh" "$p4_host" --copiar \
    "$HOME/P4_snmp.sh" "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv" \
    "$HOME/.config/zenite-p4/.env.p4-snmp" || break
  bash "$HOME/P3_eice.sh" "$p4_host" \
    'sudo -n bash "$HOME/P4_snmp.sh" preflight && sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"' || break
done
```

Resultados parciales de esta tanda en `FINAL_SNMP-01_ti_ventas02_y_ntp_interrumpido.txt`; errores posteriores de pegado en `FINAL_SNMP-DIAG_pegado_transcripcion.txt`. Las líneas de salida repetidas como comandos no son nuevas instalaciones ni validaciones. Instalar administra solo snmpd; un proceso principal ausente o conflicto previo detiene la instalación para revisar con su responsable. Los scripts validan su instalación existente sin regenerar claves ni reiniciar por repetir el comando. Si detectan cambios manuales o claves distintas, fallan sin sobrescribir.

Las cinco instalaciones de esta tanda ya tienen resultado local correcto. Salir de Visitantes con `exit`, conectar desde CloudShell a `zp-monitor-01` y, dentro de **`ubuntu@zp-monitor-01`**, consultar las seis familias de los ocho hosts de la primera tanda:

```bash
sudo -n bash "$HOME/P4_snmp.sh" recolectar --host zp-monitor-01 --host zp-ldap-01 --host zp-ventas-01 --host zp-ti-01 --host zp-ventas-02 --host zp-ntp-01 --host zp-intranet-01 --host zp-visitantes-01 &&
sudo -n bash "$HOME/P4_monitor_snmp.sh" --validar
```

La consulta no cambia servicios ni claves. Las métricas de los ocho deben pasar antes de continuar a validar el recolector; con `&&` la segunda operación solo se ejecuta si la primera termina sin fallas. Resultado recibido: seis familias de TI/Ventas-02/NTP/Intranet/Visitantes correctas a las 07:02:38–39 UTC, y ocho scrapes up a las 07:02:40 UTC. El pegado empieza a mitad de Ventas-01; no incluye la parte inicial de esta corrida ni su registro/comando. Esas secciones no se reconstruyen; monitor/LDAP/Ventas conservan pruebas completas previas. Evidencias `FINAL_SNMP-02_primera_tanda_fragmento.txt` y `FINAL_SNMP_recolector_ocho_up.txt`.

Web y VPN se reservan para segunda tanda y no se confundirán con agentes fallidos. Conservar resultados por host/hora; no aprobar SNMP-02 global de diez por una sola tanda. Después se presentarán los comandos concretos de parada de dos clientes e inicio de web/VPN para mantener capacidad dentro de la cuota.

### Segunda tanda: web y VPN, después de verificar la primera

La primera tanda ya tiene ocho scrapes up. Liberar capacidad deteniendo únicamente Ventas-02 y Visitantes, clientes recién iniciados para P4, y encender web/VPN. Monitor y LDAP permanecen disponibles; no se detienen otros proyectos ni se cambian tamaños/CPU. Desde el monitor, `exit` a CloudShell; allí:

```bash
bash "$HOME/P1_instancias.sh" detener zp-ventas-02 zp-visitantes-01 &&
bash "$HOME/P1_instancias.sh" encender zp-web-01 zp-vpn-01
```

P1 espera las paradas antes del encendido siguiente. La capacidad prevista vuelve de ocho a seis y luego a ocho instancias (16 vCPU). Conservar la salida real con estados; la parada/encendido todavía no se ha recibido y no se acredita por presentar los comandos.

Después de aproximadamente un minuto, en CloudShell consultar el monitor sin instalar ni reiniciar nada:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_monitor_snmp.sh" --validar'
```

Esto permite observar la pérdida de scrape de los dos clientes detenidos, además de verificar que el recolector sigue activo. Correlacionar con sus estados stopped de EC2; no se declara SNMP-04 completo hasta revisar el resultado y posterior recuperación de un cliente. El intervalo del scrape y su timeout pueden retrasar el cambio visible; no confundir la última muestra anterior con fallo de la parada.

#### Segundo rechazo de cuota después de la parada

P1 confirmó los dos clientes detenidos y seis instancias running, pero la llamada conjunta a iniciar web/VPN volvió a fallar. La tabla recibida precede a esa llamada; falta comprobar el estado posterior. En **CloudShell**, dos consultas de solo lectura:

```bash
date -u
aws ec2 describe-instances --region us-east-1 --filters 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query "Reservations[].Instances[].{Nombre:Tags[?Key=='Name']|[0].Value,Tipo:InstanceType,Estado:State.Name,ID:InstanceId}" --output table
aws service-quotas get-service-quota --region us-east-1 --service-code ec2 --quota-code L-1216C47A --query 'Quota.{Nombre:QuotaName,Valor:Value,Ajustable:Adjustable}' --output table
```

La cuota corresponde a On-Demand Standard; código/comando contrastados con [ejemplos oficiales AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli_service-quotas_code_examples.html). Si falta permiso de lectura, conservar el error sin pedir ampliar permisos ni asumir el valor. Puede haber diferencias de estado o consumo regional respecto del inventario anterior; ninguna causa está comprobada.

Después de esas consultas, se presenta un único intento individual de Web dentro del encendido ya autorizado:

```bash
bash "$HOME/P1_instancias.sh" encender zp-web-01
```

P1 vuelve a consultar el estado y omite el inicio si ya está running. Compartir salidas completas; no encadenar más reintentos si vuelve a fallar. VPN sigue pendiente. No se detiene otro servicio, cambia tipo/CPU ni solicita aumento de cuota.

#### Web encendido individualmente: instalar su agente

El intento individual anterior ya funcionó: Web `running` y siete instancias encendidas. La consulta GetServiceQuota fue denegada; no se obtuvo valor actual de cuota por API y no se cambian permisos. La marca al principio de la salida recibida es 07:19:58 UTC / 01:19:58 Guatemala, pero el encendido no tiene hora propia exacta. VPN continúa stopped.

En **CloudShell**, esperar los controles de Web con su ID confirmado en el inventario recibido:

```bash
aws ec2 wait instance-status-ok --region us-east-1 --instance-ids i-06b59507240cfa8e7
aws ec2 wait system-status-ok --region us-east-1 --instance-ids i-06b59507240cfa8e7
```

Copiar los archivos existentes (comprobar tamaños mayores que cero en la transferencia) y conectar:

```bash
bash "$HOME/P3_eice.sh" zp-web-01 --copiar "$HOME/P4_snmp.sh" "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv" "$HOME/.config/zenite-p4/.env.p4-snmp"
bash "$HOME/P3_eice.sh" zp-web-01
```

Dentro de **`ubuntu@zp-web-01`**, comprobar entorno e instalar solo snmpd:

```bash
sudo -n bash "$HOME/P4_snmp.sh" preflight && sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"
```

Confirmar con `si` dentro de 120 s. No modifica nginx, certificados, reglas ni EIP. El agente Web **ya terminó correctamente** a las 07:24:55 UTC; evidencia `FINAL_SNMP-01_web_agente.txt`. Preflight: Ubuntu, IP .116, paquete ausente y 4441 MiB libres. No repetir esta instalación.

#### Último agente: VPN

Salir de Web con `exit` a CloudShell. El siguiente bloque intenta iniciar solo VPN, espera controles con el ID confirmado en los inventarios recibidos y, si todo termina correctamente, copia los archivos existentes y abre EICE. No crea recursos ni modifica tipo, EIP o reglas. Si falla el encendido, el `&&` detiene los pasos siguientes; compartir la salida antes de otro intento.

```bash
bash "$HOME/P1_instancias.sh" encender zp-vpn-01 &&
aws ec2 wait instance-status-ok --region us-east-1 --instance-ids i-050e09727e2a06139 &&
aws ec2 wait system-status-ok --region us-east-1 --instance-ids i-050e09727e2a06139 &&
bash "$HOME/P3_eice.sh" zp-vpn-01 --copiar "$HOME/P4_snmp.sh" "$HOME/P4_snmp.py" "$HOME/P4_snmp_objetivos.csv" "$HOME/.config/zenite-p4/.env.p4-snmp" &&
bash "$HOME/P3_eice.sh" zp-vpn-01
```

Dentro de **`ubuntu@zp-vpn-01`**, ejecutar:

```bash
sudo -n bash "$HOME/P4_snmp.sh" preflight && sudo -n bash "$HOME/P4_snmp.sh" instalar --credenciales "$HOME/.env.p4-snmp"
```

Confirmar con `si` dentro de 120 s; administra solo snmpd, sin modificar OpenVPN. El inicio y el agente VPN **ya terminaron correctamente** a las 07:34:20 UTC; evidencia `FINAL_SNMP-01_vpn_agente.txt`. Preflight Ubuntu .132, paquete ausente y 4501 MiB libres. No repetir la instalación. Las consultas restantes no requieren Internet; priorizar cierre de ventana y después recoger métricas de Web/VPN por red privada.

Instalar los dos agentes y recoger sus seis familias completaría evidencia por host de los diez. Eso no equivale a diez scrapes simultáneos ni cambia automáticamente el criterio de SNMP-02; se documentarán los intervalos y los hosts detenidos. Si se exige simultaneidad, revisar con el humano un aumento de cuota; no se solicitó ninguno.

El rechazo de clave ya fue comprobado contra LDAP con controles válidos anterior/posterior. Aislamiento desde Ventas/Visitantes y caída EC2 siguen pendientes. Al terminar las instalaciones de ambas tandas, restaurar TI y cerrar NAT como en la sección siguiente, conservando las EIP de web/VPN.

## 7. Restaurar red antes de pruebas de aislamiento

En **CloudShell**, al terminar las instalaciones de esta ventana, restaura TI con el script de su responsable:

Las diez instalaciones ya terminaron. Salir de VPN con `exit`. El script P5 exige declarar que nmap está instalado antes de retirar Internet a TI. Este primer comando comprueba su presencia y **solo si falta instala nmap en TI** para satisfacer ese requisito de restauración; usa el NAT todavía disponible:

```bash
bash "$HOME/P3_eice.sh" zp-ti-01 'command -v nmap || sudo -n dnf -y install nmap'
```

Si termina correctamente, responder `si` a la pregunta de nmap y a la confirmación de P5. Esta restauración recrea/asocia solo la ACL TI previamente revisada, con sus cinco reglas originales; no modifica las ACL DMZ/VPN/Visitantes. Ejecutar:

```bash
bash "$HOME/P5_acls.sh" aplicar ti
bash "$HOME/P3_eice.sh" zp-monitor-01 'uname -n'
```

`aplicar ti` crea/asocia de nuevo la ACL dedicada y valida sus reglas; la prueba EICE posterior debe seguir funcionando. Su validador heredado también exige que DMZ/VPN estén en la ACL predeterminada: en FaseFinal tienen ACL dedicadas de P3, por lo que puede informar esas diferencias aunque TI quede restaurada. Conservar toda la salida, distinguir reglas/asociación TI y no cambiar otras subredes para satisfacer ese validador antiguo. Si falla la parte de TI o EICE, no informar restauración correcta; revisar ese resultado.

Después, cierra el NAT temporal **solo si pertenece a esta ventana y el equipo ya terminó de usarlo**:

```bash
bash "$HOME/P1_gateways.sh" destruir
bash "$HOME/P1_costos.sh" --resumen
bash "$HOME/P4_snmp_nube.sh" --validar
```

El destructor de P1 elimina el NAT temporal y su EIP, no las EIP de web/VPN; conserva IGW y sus rutas. Pide `si`. Su validador heredado espera DMZ sin ruta por defecto y cero EIP en toda la región: esas condiciones no corresponden a la web/VPN pública actual. Conservar los resultados de eliminación/liberación y los errores heredados tal como ocurren; no borrar EIP de web/VPN ni su ruta IGW para volverlos verdes. La validación nube de P4 describe el estado actual de Final sin exigir esos supuestos antiguos. La revisión de costos no supone que las ocho instancias ya estén detenidas: las pruebas privadas continúan.

La restauración TI y cierre NAT/EIP ya tienen resultado real recibido; faltan consultas SNMP posteriores por EICE. No agruparlos todos con `&&`, pues una diferencia heredada en el validador podría impedir cerrar el NAT aunque la restauración/eliminación efectivas hayan funcionado. No repetir automáticamente ante un error: compartir la salida para distinguirlo. Si no comenzó la ventana, no destruir recursos ajenos. No mantener NAT activo esperando aprobación del checkpoint siguiente.

**Avance real del cierre:** nmap ya estaba en `/usr/bin/nmap` a las 07:40:47 UTC. P5 creó `acl-0d435e6e99660f33f`, aplicó/verificó las cinco reglas originales y la asoció a TI. El validador solo informó las dos diferencias previstas de DMZ/VPN; no son un fallo de la política TI. No repetir P5 ni revertirlo por esos avisos. La destrucción NAT se confirmó en la salida posterior resumida abajo; falta la consulta real posterior por EICE. La restauración no tiene hora propia en el fragmento recibido.

**Cierre efectivo recibido:** P1 eliminó `nat-0c06dfd843c771516` y liberó `eipalloc-0d4b2f085e3786e66`. A las 07:47:29 UTC el validador confirma NAT vivo 0, ruta interna sin default y EIP temporal liberada; conserva FALLA por ruta DMZ y dos EIP regionales. A las 07:48:49 UTC costos muestra ocho instancias activas, NAT 0, dos EIP asociadas y cero sin asociar. El diagnóstico nube P4 de 07:50:19–07:50:27 UTC valida SG/retornos ACL y muestra NAT ausente. No repetir los comandos de cierre.

Evidencias `FINAL_SNMP_ventana_nat_cerrada.txt`, `FINAL_SNMP_costos_tras_nat.txt` y `FINAL_SNMP-DIAG_nube_20261111T075019Z.txt`. El fragmento inicial solo dice Connection closed al monitor, sin uname; la próxima consulta por EICE lo comprobará de forma explícita. Los importes del script de costos se conservan como estimaciones del script, sin validación de facturación propia.

El cierre está comprobado. En CloudShell conectar al monitor:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01
```

Dentro de **`ubuntu@zp-monitor-01`**, recoger las seis familias de Web/VPN y, si pasan, los scrapes actuales:

```bash
sudo -n bash "$HOME/P4_snmp.sh" recolectar --host zp-web-01 --host zp-vpn-01 &&
sudo -n bash "$HOME/P4_monitor_snmp.sh" --validar
```

No instala paquetes ni requiere NAT. **Resultado real recibido:** las doce secciones Web/VPN son correctas a las 07:56:41–42 UTC, con recolección exit 0 seguida de validación. Ocho scrapes up; Ventas-02 y Visitantes down a las 07:56:42 UTC, en correspondencia con EC2 stopped. EICE y consultas reales después de restaurar TI quedan comprobados. Evidencias `FINAL_SNMP-02_web_vpn_sin_nat.txt` y `FINAL_SNMP_recolector_segunda_tanda.txt`. La fase de recuperación de SNMP-04 y las pruebas de origen aún están pendientes; no se declaran diez scrapes simultáneos.

## 8. Pruebas de origen, caída y entrega a P3

### Primero: bloqueo desde Ventas, sin encender ni detener instancias

Salir del monitor con `exit` para volver a CloudShell. El bloque hace control válido desde monitor, intento desde Ventas-01 con sus credenciales instaladas y control válido posterior. Los `&&` detienen la secuencia si falla cualquiera de los pasos. No cambia claves ni reglas.

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ldap-01' &&
bash "$HOME/P3_eice.sh" zp-ventas-01 'sudo -n bash "$HOME/P4_snmp.sh" origen --host zp-ldap-01' &&
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ldap-01'
```

El intento aislado imprime OBSERVADO/PENDIENTE, no PASS automático. **Resultado recibido:** control monitor → LDAP exit 0 a las 08:02:25 UTC, Ventas → LDAP timeout exit 1 a las 08:02:33 UTC y control posterior exit 0 a las 08:02:39 UTC, 11-nov-2026. La correlación resuelve ese PENDIENTE para Ventas. Evidencia `FINAL_FW-05_ventas_controles.txt` y entrega humana `FINAL_FW-05_entrega_P3.md`; P3 cierra su fila, sin edición de su matriz por P4. SNMP-05 aún requiere Visitantes y exterior.

En CloudShell, comprobar además si existe el cliente necesario para la prueba exterior posterior:

```bash
command -v snmpget snmpwalk || echo '[PENDIENTE] Cliente SNMP ausente en CloudShell'
```

**Resultado recibido:** cliente ausente en CloudShell. Esta consulta solo informa disponibilidad local de herramientas. No instala nada ni sustituye la prueba exterior. Visitantes sigue detenido por cuota; su prueba se presentará con el intercambio concreto de capacidad después de completar la prueba exterior a Web/VPN.

### Prueba exterior a las dos EIP propias · solo CloudShell

Mantener Web, VPN y monitor encendidos. Desde CloudShell del navegador, instalar únicamente el cliente local:

```bash
sudo dnf -y install net-snmp-utils
```

CloudShell usa Amazon Linux 2023 y permite instalaciones mediante sudo/dnf; sus paquetes del sistema pueden desaparecer al reciclarse el entorno. No cambia las instancias, rutas ni NAT. Fuente: [entorno de CloudShell](https://docs.aws.amazon.com/cloudshell/latest/userguide/vm-specs.html).

Subir el archivo nuevo `P4_snmp_internet.sh` mediante **Actions → Upload file**. Ejecutar:

```bash
bash "$HOME/P4_snmp_internet.sh"
```

Confirmar `si`. Usa P3_eice.sh, P4_snmp.py revisado y las credenciales canónicas existentes de CloudShell; no hace falta subir ni mostrar las claves. Verifica el checksum del módulo antes de importarlo y nunca ejecuta el .env como shell. Descubre exclusivamente Web/VPN en la VPC prevista, exige estado running, IP privada esperada y EIP realmente asociada. Rechaza un origen con dirección local de la VPC y confirma salida IPv4 pública mediante HTTPS a checkip.amazonaws.com; guarda esa dirección de origen solo en privado. Fuente del servicio de consulta: [ejemplos AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-services-ec2-sg.html).

Para comprobar las mismas claves hace una copia temporal única de modo 600 en el monitor y la usa en cuatro controles: Web y VPN antes y después. No cambia el archivo de credenciales de servicio. Ejecuta snmpget SNMPv3 authPriv SHA-256/AES hacia UDP 161 de ambas EIP, con tiempos limitados, sin claves en argumentos. Solo acepta timeout sin datos, controles positivos y limpieza temporal confirmada. Un error de autenticación o una respuesta pública impide el resultado satisfactorio. Un timeout UDP acredita falta de respuesta desde este origen en ese intervalo; no identifica por sí solo qué filtro descarta ni todos los orígenes posibles de Internet. Correlacionar con las reglas SG/ACL verificadas.

Registra salida pública en `~/final-config/P4_snmp_internet_*/resultado.txt`. Compartir solo la salida de terminal/resultado.txt, sin origen-privado.txt, transporte-privado.txt ni credenciales. Nueve pruebas locales con red/AWS sustituidos comprobaron destinos propios, controles, clave errónea, respuesta inesperada, copia parcial, limpieza fallida y módulo alterado.

**Resultado real recibido:** registro `P4_snmp_internet_20261111T082139Z_a0tirhbv`, 11-nov-2026. Web respondió al control previo a las 08:22:06 UTC y VPN a las 08:22:12 UTC. Desde CloudShell, VPN `3.228.84.176` devolvió timeout exit 1 a las 08:22:14 UTC y Web `18.210.66.163` timeout exit 1 a las 08:22:16 UTC, sin datos SNMP. Controles posteriores correctos a las 08:22:22 UTC (Web) y 08:22:28 UTC (VPN). Copias temporales eliminadas a las 08:22:33 UTC. Evidencia `FINAL_SNMP-05_internet_web_vpn.txt`, incluida instalación correcta de net-snmp-utils 5.9.3 y primer intento sin archivo antes de su subida. SNMP-05 parte exterior comprobada en ese origen/intervalo, correlacionada con SG/ACL restringidos; Visitantes aún pendiente. La limpieza confirmada pertenece a este guion, no acredita la del rescate anterior.

### Siguiente: intercambiar VPN por Visitantes y probar su bloqueo

Después de completar las consultas a ambas EIP, pausar solo VPN con P1 para liberar dos vCPU e iniciar Visitantes, ya instalado y validado. No se abre NAT ni se reinstala el agente. Estas operaciones interrumpen temporalmente el servicio VPN mientras la instancia está detenida; se usan los scripts existentes de su responsable. En **CloudShell**:

```bash
bash "$HOME/P1_instancias.sh" detener zp-vpn-01 &&
bash "$HOME/P1_instancias.sh" encender zp-visitantes-01 &&
aws ec2 wait instance-status-ok --region us-east-1 --instance-ids i-05dc9139e9d858330 &&
aws ec2 wait system-status-ok --region us-east-1 --instance-ids i-05dc9139e9d858330
```

Cuando termine sin error, ejecutar también desde **CloudShell**, con los controles antes y después:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ldap-01' &&
bash "$HOME/P3_eice.sh" zp-visitantes-01 'sudo -n bash "$HOME/P4_snmp.sh" origen --host zp-ldap-01' &&
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ldap-01'
```

El origen usa sus credenciales privadas instaladas. No se vuelven a copiar claves. **Resultado recibido:** VPN stopped, Visitantes running, ocho encendidas. Las esperas continuaron al prompt sin error visible; no tienen hora propia. Control previo monitor → LDAP exit 0 a las 08:29:21 UTC, Visitantes timeout exit 1 a las 08:29:27 UTC y control posterior exit 0 a las 08:29:34 UTC. La correlación resuelve el PENDIENTE del guion aislado. Evidencia `FINAL_SNMP-05_visitantes_controles.txt`; SNMP-05 completo documentado en `FINAL_SNMP-05_resumen.md`, con límites de alcance.

### Siguiente: recuperación de Ventas-02 y comprobación del temporal anterior

Visitantes ya completó su prueba. Se detiene solo ese cliente y se inicia Ventas-02 en el mismo cupo de dos vCPU, usando P1. Mantener monitor activo; no se instala ningún paquete, no se abren reglas ni se crea NAT. En **CloudShell**:

```bash
bash "$HOME/P1_instancias.sh" detener zp-visitantes-01 &&
bash "$HOME/P1_instancias.sh" encender zp-ventas-02 &&
aws ec2 wait instance-status-ok --region us-east-1 --instance-ids i-05a7f9ee1a6e93000 &&
aws ec2 wait system-status-ok --region us-east-1 --instance-ids i-05a7f9ee1a6e93000
```

Después, también en **CloudShell**, control privado a Ventas-02 y lectura de los scrapes:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 'sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ventas-02 && sudo -n bash "$HOME/P4_monitor_snmp.sh" --validar'
```

**Resultado recibido:** P1 confirmó Visitantes stopped y Ventas-02 running; la consulta autenticada a Ventas-02 devolvió exit 0 y `scrape=up` a las 08:39:16 UTC / 02:39:16 Guatemala. Evidencia `FINAL_SNMP-04_ventas02_recuperacion.txt`. La recuperación requiere el dato autenticado y `zp-ventas-02 ... scrape=up`, además de EC2 running. El validador no falla solo por un target down, de modo que su OK global no basta para esta prueba. Si el primer scrape todavía está down, conservar el resultado y esperar el siguiente intervalo antes de otra lectura; no reinstalar el agente ni cambiar claves.

Comprobar por lectura que no quede el nombre temporal usado por el rescate anterior, sin mostrar contenido ni borrar archivos:

```bash
bash "$HOME/P3_eice.sh" zp-monitor-01 'if [ ! -e "$HOME/.env.p4-snmp-rescate" ] && [ ! -L "$HOME/.env.p4-snmp-rescate" ]; then echo "[OK] Temporal del rescate ausente"; else echo "[PENDIENTE] Revisar temporal del rescate sin mostrar su contenido"; fi'
```

Si existe, revisar propietario/permisos y relación con la copia canónica antes de presentar una limpieza específica; no se ejecuta el rescate de nuevo. **Resultado recibido a las 08:39:37 UTC / 02:39:37 Guatemala:** `[OK] Temporal del rescate ausente`; tanto archivo como enlace inexistentes. La recuperación y esta comprobación están acreditadas en `FINAL_SNMP-04_ventas02_recuperacion.txt`. No se repiten por revisión.

Con TI restaurada, desde **el monitor** toma control válido antes y después:

```bash
sudo -n bash "$HOME/P4_snmp.sh" control --host zp-ldap-01
```

Entre esos controles, dentro de **`ec2-user@zp-ventas-01`** y después **`ec2-user@zp-visitantes-01`**:

```bash
sudo -n bash "$HOME/P4_snmp.sh" origen --host zp-ldap-01
```

Usa las mismas credenciales privadas ya instaladas. Debe agotarse el tiempo sin datos; una credencial errónea no acredita bloqueo de red. El guion imprime `[OBSERVADO]` y recuerda que hacen falta los controles positivos. Entregar a P3 el fragmento monitor/Ventas con hora para FW-05; no editar su matriz.

SNMP-04 requiere completar la recuperación de `zp-ventas-02`: ya se recibió scrape up anterior y down posterior correlacionado con parada EC2. Los comandos de recuperación se presentarán con su estado actual antes de ejecutarlos. El monitor debe seguir activo; distinguir falta de respuesta SNMP de apagado EC2 confirmado. La prueba exterior Web/VPN ya está recibida con los controles descritos arriba.

SNMP-01 tiene diez agentes validados en intervalos, SNMP-02 cobertura de diez hosts por tandas, SNMP-03 rechazo de clave con controles y SNMP-05 los orígenes probados documentados. SNMP-04 completó la recuperación y el temporal está ausente. El conjunto está listo para revisión/aprobación; capturas gráficas aún por aportar/verificar. Guardar solo `resultado.txt` como evidencia pública, no `diagnostico-privado.txt`, `snmp.env`, perfiles temporales ni respaldos USM. En cada captura deben verse hostname, comando, hora y salida, sin claves. La recolección puede tardar varios minutos si hay hosts apagados; cada comando tiene límite y cada fallo queda registrado.

Cuando termine la sesión, detener con P1 únicamente las instancias acordadas para esa ventana; registrar el estado final. No asumir que deben apagarse servicios de otras personas. La instalación del panel tendrá su revisión después del cierre SNMP.

## 9. Fallos, límites y pruebas locales

- `instalar` requiere confirmación interactiva; `--validar` y `preflight` no cambian servicios. El diagnóstico de nube solo describe recursos. Todos escriben registros locales de evidencia.
- Conflicto con Net-SNMP previo, usuario USM existente, claves distintas, archivo adicional o puerto ocupado: se detiene para revisión. Una instalación parcial deja una marca `.failed`; no eliminarla para forzar reintentos sin inspeccionar el respaldo y el estado de paquetes.
- Fallo real de descarga/extracción del recolector: `Archivo de release con rutas inesperadas.` a las 05:11:39 UTC. El directorio raíz legítimo no tenía barra final; se reprodujo con ambos tar y se corrigió sin admitir enlaces, travesías ni nodos especiales. Pruebas de regresión: 19 casos y extracción de ambos paquetes reales. Antes de reintentar, comprobar usuario `p4monitor`, directorio de datos, archivos/unidades y estado de servicios; el instalador puede haber dejado usuario y directorios aunque no haya extraído binarios.
- El rollback de agente se hace solo después de confirmar que el proceso está detenido; restaura configuración/USM y conserva el paquete. El monitor falla dejando sus servicios detenidos y archivos parciales identificables. No se promete desinstalación ni restauración automática frente a pérdida de energía/SIGKILL.
- La puesta en servicio del agente real mediante systemd está comprobada en los diez hosts en sus respectivos intervalos; dos clientes quedaron detenidos por cuota. Prometheus/exporter ya están activos y privados en el monitor, con ocho muestras up recibidas en cada tanda. La ventana AWS quedó cerrada: TI restaurada, NAT eliminado y EIP temporal liberada. Las integraciones locales usan procesos reales con un controlador de servicio sustituido porque los contenedores no ejecutan systemd.
- Ubuntu 24.04 local: Net-SNMP real SHA-256/AES, métricas completas, rechazo de clave, idempotencia y rollback de archivos; exporter 0.31.0 y Prometheus 3.16.0 reales, con ejecución sin root como usuario de servicio, configuración validada y diez objetivos. Dirección de prueba loopback y claves sintéticas; no son datos AWS.
- Amazon Linux 2023 local: Net-SNMP real 5.9.3, autenticación v3, CPU/RAM/interfaces/procesos, idempotencia y rechazo de clave. La raíz overlay del contenedor no se expone como disco; la recolección detectó la falta e impidió un falso éxito. Se comprobó que `dskTable` responde para un montaje de prueba distinto; eso no se presenta como prueba de raíz ni sustituye la ejecución sobre EBS.
- Regresiones locales actuales: 28 casos de credenciales, permisos, orígenes, configuración previa, resultados parciales, extracción y recuperación; 14 escenarios AWS simulados, incluyendo denegación ACL prioritaria y orígenes amplios. Los nueve casos de recuperación se ejecutaron como root en contenedor aislado sin red y con servicios simulados; al ejecutar sin root se omiten. Resumen en `FINAL_SNMP_pruebas_locales.txt`.

Desde el repositorio, sin tocar servicios ni AWS:

```bash
python3 FaseFinal/configuracion/tests/P4_snmp_seguridad.py
python3 FaseFinal/configuracion/tests/P4_snmp_nube_casos.py
```

Fuentes: [release exporter 0.31.0](https://github.com/prometheus/snmp_exporter/releases/tag/v0.31.0), [release Prometheus 3.16.0](https://github.com/prometheus/prometheus/releases/tag/v3.16.0), [configuración de Net-SNMP](https://manpages.ubuntu.com/manpages/noble/man5/snmpd.conf.5.html), [perfiles de cliente](https://manpages.ubuntu.com/manpages/noble/man5/snmp.conf.5.html). Los archivos y resultados de diseño están en [P4_snmp_diseno.md](P4_snmp_diseno.md).
