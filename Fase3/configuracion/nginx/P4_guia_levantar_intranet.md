# P4 – Guía para levantar y entregar la intranet

**Zenite Prestige · AWS `us-east-1` (N. Virginia) · 29 de octubre de 2026**

La intranet ya está instalada. Detener y encender la instancia conserva Nginx, la página y la configuración en el disco EBS.
No hace falta reinstalar, volver a copiar el sitio ni crear otra instancia. El estado actual debe consultarse al iniciar.

| Dato | Valor verificado durante la instalación |
|---|---|
| Instancia | `zp-intranet-01` |
| Instance ID | `i-07330a665030d940e` |
| IP privada / URL | `10.20.0.71` · `http://10.20.0.71/` |
| VPC | `vpc-zenite-fase2` · `10.20.0.0/24` |
| Security Group | `zenite-servidores` |
| Acceso administrativo | EICE `eice-zenite-fase2`, usuario del sistema `ec2-user` |
| Configuración / archivos públicos | `/etc/nginx/nginx.conf` · `/usr/share/nginx/zenite/` |

**Ejecutar un bloque por vez, presionar Enter y esperar el prompt.** Si un comando falla, conservar su salida antes de seguir.
Las pruebas WEB-01 a WEB-05 siguen pendientes; la prueba aprobada hasta ahora es HTTP local desde la propia intranet.

## 1. Preparar CloudShell

Entrar a AWS con el **usuario IAM propio**, seleccionar **N. Virginia** y abrir CloudShell. Su prompt se parece a `~ $`.
En **Actions → Upload file**, subir estos dos archivos del repositorio si todavía no están en ese CloudShell:

- `Fase3/configuracion/P1_instancias.sh`
- `Fase3/configuracion/P1_gateways.sh`

Los comandos siguientes suponen que quedaron en el directorio inicial de CloudShell. Para volver a ese directorio:

```bash
cd "$HOME"
```

La persona necesita permisos para consultar EC2 y encender/detener las instancias que usará. Para SSH por EICE necesita
`ec2-instance-connect:SendSSHPublicKey` para la instancia y `ec2-user`, `ec2-instance-connect:OpenTunnel` para el endpoint,
y las consultas de EC2 correspondientes. Cada usuario IAM debe tener sus propios permisos: los otorgados a Cisco no se
transfieren a otra persona. Ante `AccessDeniedException`, enviar el error al administrador IAM. [Permisos de EICE](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/permissions-for-ec2-instance-connect-endpoint.html).

## 2. Encender únicamente la intranet — en CloudShell

Este comando enciende la instancia existente si está detenida y comienza su consumo de cómputo:

```bash
bash P1_instancias.sh encender zp-intranet-01
```

Esperar a que termine. Los controles de estado pueden tardar unos minutos; si la conexión falla durante el arranque,
esperar y reintentar. No ejecutar `crear` para un encendido habitual.

Consulta de solo lectura para comprobar nombre, ID, estado e IP:

```bash
aws ec2 describe-instances --region us-east-1 --filters 'Name=tag:Name,Values=zp-intranet-01' 'Name=tag:Project,Values=ZenitePrestige' 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]' --output table
```

Debe existir una sola instancia con `running`, IP `10.20.0.71` y sin IPv4 pública. Si el ID difiere del documentado,
coordinar con P1 antes de continuar; si hay varias coincidencias, no elegir una arbitrariamente.

## 3. Conectarse — desde CloudShell

```bash
aws ec2-instance-connect ssh --region us-east-1 --instance-id i-07330a665030d940e --os-user ec2-user --connection-type eice
```

Si SSH pide aceptar una huella nueva, verificar con P1 la identidad del host antes de aceptarla. No borrar una huella
existente para ignorar un aviso de cambio. La conexión por EICE usa la dirección privada y no requiere NAT.
[Conexión oficial de AWS](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html).

El prompt cambia a `[ec2-user@zp-intranet-01 ~]$`. A partir de aquí, los comandos se ejecutan **en la instancia**.

## 4. Comprobar Nginx — dentro de la instancia

Confirmar el hostname:

```bash
uname -n
```

Esperado: `zp-intranet-01`. Comprobar la configuración antes de cambiar el estado del servicio:

```bash
sudo nginx -t
```

Esperado: `syntax is ok` y `test is successful`. Si falla, no reiniciar ni recargar; revisar el error.
[Opciones de Nginx](https://nginx.org/en/docs/switches.html).

Comprobar si arrancó automáticamente:

```bash
systemctl is-active nginx
```

Esperado: `active`. **Solo si está inactivo y la configuración pasó la validación**, iniciarlo:

```bash
sudo systemctl start nginx
```

Comprobar el arranque automático:

```bash
systemctl is-enabled nginx
```

Esperado: `enabled`, como quedó durante la instalación. Si aparece `disabled`, habilitarlo para próximos encendidos:

```bash
sudo systemctl enable nginx
```

`start` inicia el servicio ahora y `enable` configura el arranque automático. No se necesita recargar si no cambió la
configuración. [Control de servicios con systemctl](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html).

## 5. Validar el sitio — dentro de la instancia

Registrar la hora:

```bash
date -u
```

Consultar el HTML y guardar el cuerpo recibido:

```bash
curl --noproxy '*' -sS --connect-timeout 5 --max-time 10 -D - -o /tmp/P4_index_obtenido.html http://127.0.0.1/
```

Esperado: `HTTP/1.1 200 OK`. Mostrar el título:

```bash
head -n 12 /tmp/P4_index_obtenido.html
```

Debe contener `<title>Zenite Prestige | Intranet</title>`. `Welcome to nginx!` indica que está activo el sitio
predeterminado y la verificación no queda aprobada, aunque responda 200.

Comprobar también los recursos públicos:

```bash
curl --noproxy '*' -sS -I --connect-timeout 5 --max-time 10 http://127.0.0.1/styles.css
```

```bash
curl --noproxy '*' -sS -I --connect-timeout 5 --max-time 10 http://127.0.0.1/intranet.js
```

Ambos deben devolver HTTP 200; CSS debe servirse como `text/css` y JavaScript con su tipo correspondiente.
Estas dos comprobaciones quedan pendientes de evidencia real en AWS al redactar esta guía.
Las opciones de curl evitan proxies y limitan el tiempo de espera. [Manual de curl](https://curl.se/docs/manpage.html).

## 6. Entrega a P5 / siguiente persona

La página se sirve por **HTTP TCP 80**. P5 debe verificar estas entradas de `zenite-servidores`:

| Origen autorizado | Regla necesaria |
|---|---|
| `zenite-ventas` | TCP 80 |
| `zenite-ti` | TCP 80 |
| `zenite-servidores` | TCP 80, autorreferencia |

El grupo es compartido con otros servidores: revisar el efecto en todas las instancias asociadas. Esta guía no modifica
Security Groups ni ACL. La última salida compartida de reglas no incluía TCP 80; el estado actual debe consultarlo P5.
Conservar SSH desde el EICE. No agregar entrada pública ni acceso desde toda la VPC.

Para las pruebas cruzadas, coordinar con los responsables el encendido de cada cliente y sus permisos IAM. Entrar al
cliente por EICE y ejecutar **dentro de ese cliente**, no en CloudShell:

```bash
uname -n
```

```bash
date -u
```

```bash
curl --noproxy '*' -i --connect-timeout 5 --max-time 10 http://10.20.0.71/
```

| Prueba pendiente | Cliente | Usuario SSH | Esperado |
|---|---|---|---|
| WEB-01 | `zp-ventas-01` | `ec2-user` | HTTP 200 y página de Zenite |
| WEB-02 | `zp-ti-01` | `ec2-user` | HTTP 200 |
| WEB-03 | `zp-ldap-01` | `ubuntu` | HTTP 200 |
| WEB-04 | `zp-visitantes-01` | `ec2-user` | Tiempo agotado por bloqueo de red |

Un HTTP 403 desde Visitantes confirma que llegó a Nginx y fue rechazado por la restricción del sitio; no cumple el
tiempo agotado exigido por WEB-04. Si aparece, P5 debe revisar el bloqueo de red. Para WEB-05, revisar evidencia de AWS:
ausencia de direcciones públicas, entradas públicas y mecanismos de publicación, además del intento externo.
No llenar resultados sin ejecutarlos ni sustituirlos con la prueba de localhost. Evidencias en
`Fase3/evidencias/04_intranet/`; registrar hostname, comando, salida y hora. La matriz compartida la actualiza P6.

## 7. NAT opcional — solo si se necesita descargar paquetes

Nginx ya está instalado y el sitio no descarga recursos externos. La administración por EICE y las conexiones HTTP
entre subredes usan la red privada. Para esas tareas no hace falta crear el NAT.

Si se necesita Internet, volver primero a CloudShell con `exit`. Consultar el estado:

```bash
bash P1_gateways.sh --validar
```

Si el NAT no existe, aparece `[FALLA]` en ese punto; esto es esperado en una sesión sin Internet. Coordinar con P1 y,
solo cuando se necesite, ejecutar el comando que crea o reutiliza NAT, Elastic IP y rutas:

```bash
bash P1_gateways.sh crear
```

Revisar el plan, confirmar con `si` y esperar `RESULTADO: todo correcto.` El NAT y la IPv4 pública generan cargos
mientras existen. No usar la Elastic IP del NAT como URL de la intranet.

## 8. Cerrar la sesión — en CloudShell

Si el prompt todavía muestra `ec2-user@zp-intranet-01`, regresar a CloudShell:

```bash
exit
```

Detener únicamente la intranet, una vez que nadie la esté usando:

```bash
bash P1_instancias.sh detener zp-intranet-01
```

**Si existe NAT y nadie más lo necesita**, eliminarlo y liberar su Elastic IP:

```bash
bash P1_gateways.sh destruir
```

El script pide `si`; conservará el Internet Gateway. Si el NAT ya está eliminado, el procedimiento de P1 comprueba su
ausencia. No eliminar un NAT usado por otra persona.

Verificar el cierre:

```bash
bash P1_gateways.sh --validar-apagado
```

```bash
bash P1_instancias.sh --validar
```

Esperado: intranet `stopped`, NAT vivo 0 y Elastic IP liberada. Si hay otras instancias activas, coordinar con sus
responsables; no detenerlas automáticamente. `P1_instancias.sh --validar` revisa también otras instancias de Fase 3,
por lo que una falla de otro servicio se comunica a su responsable.

**Detener conserva el trabajo. Borrar el disco EBS sí borra los archivos que contiene.** No terminar la instancia ni
eliminar su volumen para cerrar una sesión. Los discos conservados siguen generando cargos de almacenamiento;
el cierre no elimina cargos ya acumulados. Cerrar CloudShell por sí solo tampoco detiene EC2 ni elimina el NAT.
[Estados de EC2 y facturación](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-lifecycle.html).

## Si algo falla

| Síntoma | Comprobación / siguiente acción |
|---|---|
| `No such file` al ejecutar P1 | Confirmar que se está en CloudShell, subir el script y ejecutar `cd "$HOME"`. |
| `AccessDeniedException` | Enviar el mensaje completo al administrador IAM; no cambiar reglas de red para resolver un permiso IAM. |
| `nginx -t` falla | Conservar el error y revisar con P4 antes de recargar. |
| HTTP 200 con `Welcome to nginx!` | Comparar `/etc/nginx/nginx.conf` con la configuración de P4; revisar con P4 antes de sobrescribir. |
| Localhost funciona, Ventas/TI no | P5 debe revisar entrada TCP 80, salida del cliente, ACL y tráfico de retorno. |
| Error de conexión al arrancar | Comprobar que EC2 esté `running` y esperar los controles de estado. |

Para diagnóstico del servicio, dentro de la intranet:

```bash
sudo systemctl status nginx --no-pager
```

Para comprobar los archivos públicos:

```bash
sudo ls -l /usr/share/nginx/zenite
```

Deben existir `index.html`, `styles.css` e `intranet.js`. El historial de instalación y las pruebas realizadas están en
[README.md](README.md); el procedimiento general de sesiones del equipo está en [P1_sesiones.md](../P1_sesiones.md).
