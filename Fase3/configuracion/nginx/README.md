# P4 – Intranet de Zenite Prestige

**Para la siguiente persona:** [guía de comandos para encender, verificar y apagar la intranet](P4_guia_levantar_intranet.md).

Estado: **checkpoint 3 completado con salida compartida por el usuario**. Nginx instalado, servicio activo, paquete
transferido por EICE y sitio publicado; `nginx -t` correcto y HTTP 200 con el título de Zenite desde `127.0.0.1`.
Pendientes: revisión visual del sitio desplegado, respuesta de CSS/JavaScript y pruebas WEB-01 a WEB-05 desde sus orígenes.

## Decisiones aprobadas

- Nginx en `zp-intranet-01`, Amazon Linux 2023, IP privada `10.20.0.71`.
- HTTP, puerto TCP 80, como el reparto de tareas y la matriz WEB-01 a WEB-05. Es una desviación de HTTPS en Fase 1:
  no cifra el tráfico y se limita a contenido ficticio de laboratorio, sin formularios de acceso ni contraseñas.
- Página estática con inventario de vehículos, repuestos y espacios de taller. Todo dato comercial es ficticio;
  no hay base de datos, reservas reales, autenticación LDAP ni persistencia.
- Restricción adicional en Nginx por dirección de origen: localhost, Ventas, TI y Servidores.
- WEB-03 se ejecutará desde `zp-ldap-01` (`10.20.0.69`, Ubuntu, usuario `ubuntu`).

## Archivos y destino previsto

| Archivo | Uso | Destino en `zp-intranet-01` |
|---|---|---|
| `index.html` | Página y datos de demostración | `/usr/share/nginx/zenite/index.html` |
| `styles.css` | Diseño adaptable a escritorio y móvil, fuentes del sistema | `/usr/share/nginx/zenite/styles.css` |
| `intranet.js` | Búsqueda y filtro por marca, sin peticiones de red | `/usr/share/nginx/zenite/intranet.js` |
| `nginx.conf` | Configuración completa, un único sitio HTTP | `/etc/nginx/nginx.conf` |

**Solo se publican los tres archivos de la página.** No copiar este README, scripts, archivos `.env` ni configuraciones
al directorio público. `nginx.conf` sustituye la configuración predeterminada de esa instancia. En el checkpoint 3 se
comprobó que `conf.d` y `default.d` estaban vacíos y el usuario ejecutó el respaldo de la configuración antes de publicar.
No incluye otros sitios.

## Revisión local

Abrir `index.html` en un navegador o, desde la raíz del repositorio, ejecutar:

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory Fase3/configuracion/nginx
```

Visitar `http://127.0.0.1:8080/`. Detener el servidor con `Ctrl+C` al terminar. Este servidor sirve solamente para
revisar la página en la máquina local; no valida Nginx ni las restricciones de red y no debe usarse en AWS.

Revisar:

1. Navegación a Inventario, Repuestos y Taller, tanto en escritorio como en móvil.
2. Seis vehículos en total; cada filtro de marca muestra dos. Buscar `Taycan` muestra uno; `electrica` también lo encuentra.
3. Una búsqueda sin coincidencias muestra el mensaje correspondiente y el contador en cero.
4. Borrar la búsqueda y seleccionar «Todas» recupera las seis filas. Con JavaScript desactivado sigue visible el inventario.
5. No se necesitan CDN, fuentes descargadas ni Internet. No hay botones que simulen guardar o reservar datos.

Verificación local del checkpoint 2 (28 de octubre de 2026): estructura HTML, IDs, enlaces internos y archivos de recursos
comprobados con un analizador; `node --check intranet.js` sin errores. Búsqueda, filtro combinado, normalización de acentos,
ausencia de resultados y restablecimiento comprobados con Node y un DOM simulado. Esto no sustituye la revisión visual
en navegador ni las pruebas de servicio y red en AWS. No se generaron evidencias de AWS.

### Prueba local solicitada el 29 de octubre de 2026

Se ejecutó un servidor HTTP temporal de Python, limitado a `127.0.0.1`, publicando copias únicamente de los tres archivos
del sitio. HTML, CSS y JavaScript devolvieron HTTP 200 y contenido idéntico a sus fuentes. Se repitieron las pruebas de
filtro por las tres marcas, búsqueda combinada, acentos, código, contador, cero coincidencias y restablecimiento con un
DOM simulado en Node. Firefox sin ventana cargó la página en escritorio (1440×1400) y móvil (390×2300); las capturas se
inspeccionaron visualmente. No se observaron superposiciones; en móvil los paneles se apilan y la tabla tiene su propio
contenedor de desplazamiento horizontal. Las capturas cubren el tamaño de la ventana, no toda la página.

Resultados y capturas: `../../evidencias/04_intranet/local_pc/20261029_013806/`. El servidor se detuvo y los perfiles
temporales se eliminaron al terminar. El entorno local no tiene Nginx instalado: esta prueba de la página no valida
su configuración, las cabeceras del servidor desplegado ni Security Groups/ACL, y no equivale a WEB-01 a WEB-05.

## Instalación en AWS: checkpoint 3

Los comandos se ejecutaron por el usuario, separados entre CloudShell y la terminal de la instancia, usando los scripts
de P1 existentes. Este registro permite reproducir la instalación; no constituye una autorización para modificar otros servicios.

Precondiciones:

- Consola en **N. Virginia (`us-east-1`)**. Confirmar que la instancia sigue en `10.20.0.71`, sin IP pública.
- P1 dispone del NAT para instalar paquetes y la instancia está encendida. Para entrar se usa EICE, usuario `ec2-user`.
- Validar la configuración candidata con `nginx -t` antes de activar el servicio; verificar luego su estado y
  `curl --noproxy '*' -i --connect-timeout 5 --max-time 10 http://127.0.0.1/` (esperado: HTTP 200 y título de Zenite).
- Nginx y HTTP se comprobaron en AWS con las salidas compartidas por el usuario. El entorno local no tiene Nginx instalado.

### Transferir desde CloudShell sin NAT

El paquete se genera localmente, desde esta carpeta, con:

```bash
tar -czf P4_intranet.tar.gz index.html styles.css intranet.js nginx.conf
```

El archivo generado está ignorado por git; sus fuentes sí se versionan. Subir `P4_intranet.tar.gz` y
`P4_subir_intranet.sh` al mismo directorio de CloudShell con **Actions → Upload file**. Si se está dentro
de la instancia, ejecutar antes `exit` para regresar a CloudShell. Después:

```bash
bash P4_subir_intranet.sh --validar
bash P4_subir_intranet.sh subir
```

`subir` pide `si`, envía una llave pública temporal mediante EICE y copia el paquete a
`/home/ec2-user/P4_intranet.tar.gz` con SCP sobre el túnel privado. La llave privada temporal permanece únicamente
en un directorio de `/tmp` con permisos restrictivos y se elimina al terminar; no se muestra ni se versiona.
La identidad del host se compara con la huella ya registrada al conectarse por EICE desde ese CloudShell.
El script busca VPC, instancia y endpoint por nombre y se detiene ante discrepancias. Registro:
`~/fase3-config/P4_transferencia.log`. El modo `--validar` solo consulta AWS; no prueba los permisos de transferencia.
El NAT no se necesita para esta copia. El paquete todavía no se publica y Nginx no se modifica con este script.

Validación local del script (29 de octubre de 2026): `bash -n` sin errores y seis casos con comandos simulados:
validación sin envío, instancia detenida, nombre duplicado, transferencia exitosa, llave rechazada y fallo de SCP.
En los tres casos que generan una llave se comprobó su limpieza al terminar. Estas simulaciones no contactaron AWS;
el usuario confirmó después `[OK] Paquete copiado a /home/ec2-user/P4_intranet.tar.gz` y `RESULTADO: transferencia correcta`.
La publicación y la respuesta HTTP del HTML quedaron verificadas posteriormente (ver resultados al final de esta sección).

### Extraer y comprobar antes de publicar

Conectarse nuevamente a `zp-intranet-01` por EICE. Dentro de la instancia, como `ec2-user`:

```bash
mkdir -p "$HOME/p4-intranet"
tar -xzf "$HOME/P4_intranet.tar.gz" -C "$HOME/p4-intranet"
sudo nginx -t -c /home/ec2-user/p4-intranet/nginx.conf
sudo ls -la /etc/nginx/conf.d /etc/nginx/default.d
sudo rpm -Vf /etc/nginx/nginx.conf
```

La configuración candidata debe pasar `nginx -t`. La lista de directorios y la verificación de RPM permiten detectar
configuraciones ajenas antes de sustituir la predeterminada. Si aparecen archivos `.conf` adicionales o modificaciones
del paquete, se revisan primero. No sobrescribir configuraciones ajenas. La publicación posterior conservará un respaldo
de `/etc/nginx/nginx.conf`, instalará únicamente los tres archivos públicos y validará de nuevo antes de iniciar Nginx.

El primer `nginx -t` real devolvió `syntax is ok` y `test is successful`, con un aviso sobre `types_hash`.
Se preparó el ajuste `types_hash_max_size 4096` y `types_hash_bucket_size 128` en la configuración del repositorio;
se aplicó también a la copia transferida y el usuario repitió `nginx -t` sin el aviso.
El usuario repitió `rpm -Vf /etc/nginx/nginx.conf`: devolvió `.M...U... g /var/log/nginx/error.log`, indicando diferencias
de modo y propietario en el log; esa salida no señaló cambios en `nginx.conf`.

Durante la publicación se pegaron unidos `nginx -t -c .../nginx.conf` y `sudo cp -a ...`.
Nginx devolvió `invalid option: "cp"`; ese respaldo no se ejecutó. Después `sudo nginx -t` validó la configuración
instalada y `systemctl enable --now nginx` creó el enlace del servicio. La revisión posterior mostró la configuración
predeterminada, carpeta del sitio ausente y servicio `active`. Se repitió la publicación con comandos separados.
El usuario ejecutó el respaldo, creó la carpeta y copió los archivos, pero inicialmente omitió instalar `nginx.conf`:
el primer HTTP 200 sirvió `Welcome to nginx!`. Tras instalar la configuración de P4 y recargar, se obtuvo la página correcta.
Ejecutar cada comando por separado, esperando el prompt para pegar el siguiente.

### Resultados locales recibidos

| Intento | Hora de la cabecera HTTP (UTC) | Obtenido | Evaluación |
|---|---|---|---|
| 1 | 2026-10-29 07:24:31 | HTTP 200, 896 bytes, título `Welcome to nginx!` | Fallo de publicación: configuración predeterminada activa |
| 2 | 2026-10-29 07:26:32 | HTTP 200, 8456 bytes, UTF-8, título `Zenite Prestige \| Intranet` | Prueba local de HTML aprobada |

El segundo intento corresponde a las 01:26:32 de Guatemala. La hora procede de la cabecera `Date` del servidor;
no se inventó una hora de ejecución. Se recibieron también `nginx -t` correcto y recarga sin error. El estado `active`
del servicio se verificó en la salida anterior. El CSS y JavaScript desplegados y los orígenes de WEB-01 a WEB-05 siguen
pendientes. Transcripciones del chat en `../../evidencias/04_intranet/FASE3_WEB-LOCAL_intento*.txt`.
La captura del usuario `configuracion_web.png` muestra la corrección y la misma respuesta HTTP; se conservó el original
y se creó una copia idéntica con nombre `FASE3_WEB-LOCAL_Intranet_HTTP200.png`.

No se llena la matriz compartida con esta prueba: `localhost` no sustituye las conexiones desde Ventas, TI y LDAP.

## Coordinación con P5 y pruebas posteriores

P5 debe permitir entrada TCP 80 en `zenite-servidores` desde `zenite-ventas`, `zenite-ti` y `zenite-servidores`
(autorreferencia). No se solicita entrada desde Visitantes, Internet ni desde toda la VPC. Al ser un Security Group
compartido, estas reglas alcanzan a las demás instancias asociadas; P5 debe tenerlo presente al revisar los puertos.
No se modifican los Security Groups ni las ACL desde este paquete.

| Prueba | Origen | Resultado esperado y estado |
|---|---|---|
| Local | `zp-intranet-01` → `127.0.0.1:80` | HTTP 200 y página de Zenite: verificado en intento 2 |
| WEB-01 | `zp-ventas-01` → `10.20.0.71:80` | HTTP 200 y página de Zenite |
| WEB-02 | `zp-ti-01` → `10.20.0.71:80` | HTTP 200 |
| WEB-03 | `zp-ldap-01` → `10.20.0.71:80` | HTTP 200 |
| WEB-04 | `zp-visitantes-01` → `10.20.0.71:80` | Tiempo agotado por bloqueo de red |
| WEB-05 | Internet → Intranet | Sin acceso, corroborado con configuración de AWS |

Nginx devuelve **HTTP 403** si una dirección no autorizada logra llegar al servicio. Es una capa adicional, pero **no
cumple el tiempo agotado de WEB-04**: un 403 requiere revisar las reglas de P5 antes de dar la prueba por aprobada.
No se confía en cabeceras de cliente para determinar su IP y no hay proxy intermedio configurado.

Para WEB-05 no basta que un equipo externo no alcance una dirección privada: también deben revisarse las interfaces
sin IPv4 pública ni IPv6 pública, todos los grupos asociados sin entradas públicas, las rutas y cualquier mecanismo de
publicación existente. No usar la Elastic IP del NAT como si fuera la dirección de entrada de la intranet.

Las pruebas de red y capturas se hacen en los checkpoints 3 y 4; el reporte y la bitácora en el 5. Una vista local de la
página no es evidencia WEB-01 a WEB-05. Las capturas reales deben mostrar host, comando, salida y hora; en consola,
también N. Virginia. Sus archivos se guardarán en `Fase3/evidencias/04_intranet/`.

## Documentación consultada

- Nginx, contenido estático y estructura de configuración: https://nginx.org/en/docs/beginners_guide.html
- Nginx, orden de `allow` y `deny`: https://nginx.org/en/docs/http/ngx_http_access_module.html
- Nginx, `listen`, `root`, `try_files` y `limit_except`: https://nginx.org/en/docs/http/ngx_http_core_module.html
- Nginx, `add_header`: https://nginx.org/en/docs/http/ngx_http_headers_module.html
- Nginx, opciones `-t` y `-c`: https://nginx.org/en/docs/switches.html
- AWS CLI, túnel EICE: https://docs.aws.amazon.com/cli/latest/reference/ec2-instance-connect/open-tunnel.html
- AWS CLI, llave pública temporal (60 segundos): https://docs.aws.amazon.com/cli/latest/reference/ec2-instance-connect/send-ssh-public-key.html
- OpenSSH, SCP: https://man.openbsd.org/scp
- systemd, control del servicio: https://www.freedesktop.org/software/systemd/man/latest/systemctl.html
- RPM, verificación de archivos del paquete: https://rpm.org/docs/latest/man/rpm.8
- Nginx, ajuste de tablas hash: https://nginx.org/en/docs/hash.html
