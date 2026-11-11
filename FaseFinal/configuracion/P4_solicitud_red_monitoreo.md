# P4 → P1/P3 · Coordinación de monitoreo

Estado: diseño B aprobado por el humano; solicitud preparada para coordinar. **No enviada ni ejecutada.** El humano indicó «yo lo puedo hacer» para operar la ventana. Los comandos existentes y su alcance concreto están explicados en `P4_snmp_operacion.md`; falta el inventario actual antes de aplicarlos. Se mantiene la coordinación del uso compartido de NAT/ACL y la revisión de cualquier regla adicional.

## Texto para P3

> P4 ya terminó la revalidación LDAP. Estamos preparando SNMPv3 authPriv y, después, Grafana privado en `zp-monitor-01` (`10.20.0.103`). Recibimos tu entrega de F-07/F-08 y no solicitamos abrir UDP 162, TCP 3000, 9090 ni 9116.
>
> Necesitamos verificar las reglas efectivas UDP 161 desde `zenite-ti` hacia `zenite-ventas`, `zenite-visitantes`, `zenite-servidores`, `zenite-dmz`, `zenite-vpn` y `zenite-ti`, y retorno UDP efímero de los agentes hacia TI. También comprobar los miembros/ENI de `zenite-ti` dentro de `10.20.0.96/28`.
>
> Para instalar paquetes en monitor y cliente TI necesitamos una ventana temporal de salida a repositorios, coordinada con el NAT de P1. Por favor propón el cambio mínimo y la restauración de ACL TI que ejecutarás; el calendario menciona revertir TI, pero P4 no ejecutará una reversión global ni cambiará tus scripts. Al terminar deben quedar restauradas las restricciones y seguir funcionando EICE y SNMP.
>
> Si ya están todos los paquetes o podemos trasladarlos con dependencias verificadas sin salida adicional, lo confirmamos antes de pedir una excepción. No asumir que un archivo `.deb` aislado resuelve todas las dependencias.
>
> Entregaremos FW-05 con hora y salida real: consulta exitosa desde el monitor y agotamiento de tiempo desde Ventas. La configuración v3 limitará permisos por usuario/vista y la escucha por IP privada; el CIDR de origen se cumple mediante SG/NACL, pues `rouser` no tiene parámetro SOURCE.

## Flujos a verificar con P3

| Flujo | Protocolo / puerto | Origen → destino | Situación |
|---|---|---|---|
| Consultas SNMP | UDP destino 161 | TI / monitor `10.20.0.103` → diez agentes privados | F-07 reportada aplicada; comprobar estado efectivo. |
| Respuestas SNMP | UDP destino efímero | Agentes → TI `10.20.0.96/28` | ACL sin estado: revisar ambos sentidos y pruebas, sin reutilizar números de regla a ciegas. |
| Disponibilidad auxiliar | ICMP | TI → agentes, según reglas existentes | F-08 documentada para DMZ/VPN; el criterio principal seguirá siendo consulta SNMP. |
| Administración / túnel | TCP 22 | EICE → instancias; túnel al monitor | Reutilizar reglas existentes y verificar después de cambios. |
| Instalación temporal | HTTPS/HTTP y retornos necesarios | TI → repositorios mediante salida coordinada | P3 define destinos/puertos y restauración; pendiente de ventana y comprobación. |
| Grafana / Prometheus / exporter | TCP 3000/9090/9116 | Solo loopback del monitor | No abrir SG ni NACL. Grafana mediante SSH por EICE. |

Si el inventario o una regla contradicen el origen TI previsto, devolver el conflicto antes del despliegue. P4 no añade una regla alternativa desde otra subred ni permite `0.0.0.0/0`.

## Texto para P1

> P4 usará el monitor existente, sin crear otra instancia. Confirmemos tipo, disco, espacio libre y estado por nombre; el plan registra `t3.small`/16 GiB y la última salida del humano lo muestra detenido.
>
> Para agentes necesitamos las diez instancias del CSV de P4, encendidas solo durante la ventana acordada y las pruebas. Propongo un piloto en monitor y un agente, seguido del resto. Por favor confirma coordinación con los demás responsables antes de encender hosts que sostienen sus servicios.
>
> Las instancias privadas necesitarán una sesión NAT si faltan paquetes; coordinar con P3 la ACL TI y confirmar el presupuesto disponible. Web/VPN deberían usar sus EIP, sujeto a verificar rutas actuales.
>
> Al terminar la ventana se elimina solo el NAT temporal y se comprueba cierre con tus herramientas de FaseFinal, conservando las EIP de web/VPN. La instalación de Grafana queda para su checkpoint, con otra ventana si hiciera falta; no dejamos NAT activo esperando una aprobación.
>
> Para SNMP-04 propongo detener y volver a encender `zp-ventas-02` como cliente de prueba, cuando sus agentes ya estén validados. Confirma que se puede usar y cuál era su estado inicial; se registra parada/recuperación y se devuelve al estado acordado.

El calendario de P1 pide aviso con 15 minutos de anticipación y ventanas de hasta 3 h. Los horarios históricos ya anotados allí no se dan por confirmados para esta sesión. El humano coordina el aviso; este documento no envía mensajes.

## Acceso de TI a Grafana

El humano usa **Fedora**. El túnel se abrirá en su terminal nativa con OpenSSH y AWS CLI v2, y Grafana se verá en su navegador en `http://127.0.0.1:3000`. La instalación remota seguirá en CloudShell.

El responsable IAM debe confirmar qué identidad de TI puede usar EICE y autorizar la llave pública temporal para `ubuntu` en el monitor. El hardening SSH debe permitir el reenvío necesario; se revisará antes de proponer un cambio. P4 no modificará IAM ni abrirá puertos nuevos para evitar este requisito. Las credenciales de la consola no se copian por el chat ni se presumen disponibles en Fedora.

## Entrega a P5

El checkpoint 3 de LDAP quedó revisado y el humano pidió continuar con todo P4; R1 conserva su limitación histórica. Para SNMP/Grafana todas las filas siguen pendientes hasta recibir salidas reales. La tabla de criterios está en `P4_snmp_diseno.md`; P4 preparará resultados y P5 actualizará la matriz compartida.
