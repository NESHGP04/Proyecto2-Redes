# VPN para trabajadores remotos y firewall final

Persona 3 · Fase final · Horas en UTC (Guatemala es UTC−6). Todas las salidas citadas están en `FaseFinal/evidencias/03_vpn_firewall/`.

## 1. Objetivo de esta parte

- Dar a un trabajador remoto acceso **solo a la Intranet** (`zp-intranet-01`, `10.20.0.71:80`) mediante una VPN propia (OpenVPN en `zp-vpn-01`). Sin VPN la Intranet no se alcanza desde Internet y por la VPN nunca se llega a TI.
- Ser la dueña única del **firewall final**: Security Groups y ACL de la DMZ, la VPN y el monitoreo. Las únicas entradas públicas son las excepciones de D10: TCP 80 y 443 hacia la web y UDP 1194 hacia la VPN. EICE debe seguir funcionando.
- Repetir la regresión de las pruebas de seguridad de Fase 3 y documentar qué cambió a propósito.

## 2. Recursos y servicios

| Recurso | Valor |
|---|---|
| Servidor VPN | `zp-vpn-01` `i-050e09727e2a06139`, Ubuntu 24.04.5, t3.micro, `10.20.0.132` en `subnet-zenite-vpn` (`subnet-061f6bea484702eec`, `10.20.0.128/28`) |
| Nombre público | `zenite-vpn.dernait.com` → EIP `3.228.84.176` (de P1). Sale a Internet por `rt-zenite-vpn → IGW`, sin NAT |
| Software | OpenVPN 2.6.19 y easy-rsa 3 (apt de Ubuntu); servicio `openvpn-server@zenite` |
| Pool de clientes | `10.30.0.0/27` (servidor `10.30.0.1`); hasta 10 clientes |
| Security Groups | `zenite-dmz` `sg-06c3d521d3586f2b5`, `zenite-vpn` `sg-044aad87e64e20906`, `zenite-servidores` `sg-0bd52634dd2e6bb61`, `zenite-ti` `sg-0e73e9942dd403016`, `zenite-eice` `sg-0697e7f5646e28ab4`, más `zenite-ventas` y `zenite-visitantes` |
| ACL nuevas | `acl-zenite-dmz` `acl-05c8ba767f1345c57` (20 entradas) y `acl-zenite-vpn` `acl-0d68b812eba2c9ddb` (21 entradas). Antes, las dos subredes usaban la ACL predeterminada `acl-067acfb0422ab4b7e` |
| Etiquetas | `Name`, `Project=ZenitePrestige`, `Phase=Final`, `Environment=Prototype`, `Owner=Grupo30` en las ACL nuevas |
| Cliente de prueba | Mac del equipo con `openvpn` 2.7.9 (Homebrew), perfiles `trabajador01` (válido) y `revocado01` (revocado) |

## 3. Decisiones

| ID | Decisión | Motivo |
|---|---|---|
| D6 | Autenticación **solo con certificados**: CA propia (EC `prime256v1`), `verify-client-cert require`, `remote-cert-tls client`, CRL (`crl-verify`) | Es suficiente para el prototipo y permite revocar a un trabajador sin tocar a los demás. La autenticación LDAP (mejora opcional) no se hizo por tiempo. |
| D7 | **MASQUERADE** en `zp-vpn-01` (`10.30.0.0/27 → 10.20.0.0/24`), `ip_forward=1` | La VPC no necesita rutas hacia `10.30.0.0/27` ni desactivar *source/dest check*. Las reglas de la VPC se escriben para el origen `zenite-vpn` (`10.20.0.132`). |
| — | ***Split tunnel***: se empuja solo `10.20.0.0/24` | El tráfico de Internet del trabajador no pasa por AWS (menos costo y menos riesgo). Comprobado: `route get 18.210.66.163` sale por `en0`. |
| — | **Perfil "solo Intranet"**: `iptables` en la VPN deja pasar solo `10.20.0.71` TCP 80; TI (`10.20.0.96/28`) se descarta primero; el resto se descarta | Mínimo privilegio. Hay doble control: además de iptables, `zenite-ti` no admite nada desde `zenite-vpn` y `acl-zenite-vpn` niega la VPC salvo TCP 80 hacia Servidores. |
| — | Protección del canal: `tls-crypt`, `tls-version-min 1.2`, `data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305`, `dh none` (ECDHE) | Con `tls-crypt`, un paquete sin la llave compartida se descarta antes del TLS; reduce el escaneo y el DoS en UDP 1194. |
| — | Se aplican **las dos ACL** (DMZ y VPN), de a una, comprobando EICE y el servicio después de cada una | Lo pidió el humano. Da defensa en profundidad para las dos únicas subredes con IP pública. |
| — | SNMP (F-07): UDP 161 **solo desde `zenite-ti`** hacia todos los grupos, e ICMP desde TI hacia DMZ y VPN | Valor por defecto mientras P4 no pida otra cosa. Se agregó también a `acl-zenite-visitantes` (entrada 130, y salida 130 para el retorno). |
| — | `allow 10.20.0.128/28` en el nginx de la Intranet lo hizo P3, con aviso a P2 | Lo decidió el humano. Sin esa línea la Intranet responde 403 a la VPN, por la NAT. |
| — | AWS Client VPN se **descarta** | Ver la sección 6 (costo). Además, el proyecto pide configurar el servicio nosotros. |

## 4. Implementación

### 4.1 Archivos

| Archivo | Qué hace |
|---|---|
| `FaseFinal/configuracion/P3_firewall_final.sh` | `--validar [paso\|todo]` (solo lectura, es el modo por defecto), `aplicar <paso>`, `--revertir <paso>`. Pasos: `base`, `vpn`, `monitoreo`, `acl-dmz`, `acl-vpn`. Busca por nombre; pide `si`; guarda el JSON del antes y el después en `~/final-config/p3-sg-*.json` y `p3-acl-*.json`; deja log en `P3_firewall_final.log`. Las funciones de ACL vienen de `P5_acls.sh`. Una ACL nueva se asocia a la subred **solo cuando ya tiene todas sus entradas**. `--revertir base` pide una segunda confirmación antes de quitar 80 y 443. |
| `FaseFinal/configuracion/P3_eice.sh` | Para CloudShell: `P3_eice.sh <zp-nombre> ['comando' \| --copiar <archivos> \| --traer <remota> <destino>]`. Usa una llave temporal (`send-ssh-public-key`) y `ssh` con `ProxyCommand=aws ec2-instance-connect open-tunnel`. Cada salida empieza con `== <hostname> · <hora UTC>`. |
| `FaseFinal/configuracion/vpn/P3_vpn_servidor.sh` | Corre dentro de `zp-vpn-01` y verifica `uname -n` y la IP. Modos: `--validar` (por defecto), `instalar`, `cliente <nombre>`, `revocar <nombre>`. Es idempotente. Los `.ovpn` quedan en `/root/zenite-clientes/` con modo 600 y nunca se imprimen. `revocar` publica la CRL nueva sin reiniciar el servicio. |
| `FaseFinal/configuracion/vpn/zenite.conf` | Configuración del servidor. Todas las rutas son absolutas (ver 5.2). |
| `FaseFinal/configuracion/vpn/zenite-vpn-up.sh` | Script `up` (corre como root antes de bajar privilegios). Es idempotente. Crea las cadenas `ZENITE-VPN-FWD` y `ZENITE-VPN-IN` y la regla MASQUERADE. |
| `FaseFinal/configuracion/vpn/.gitignore` | `*.ovpn`, `*.key`, `*.pem`, `*.p12`, `pki/`. En el repositorio no hay llaves, perfiles ni CA. |

### 4.2 Orden de ejecución (2026-11-09)

1. Estado inicial, solo lectura (07:48:20): `P3_firewall_final.sh --validar` dio 17 fallas, todas esperadas (reglas que todavía no existían). `P5_security_groups.sh --validar` no dio fallas.
2. `aplicar base` (07:50:34) y `aplicar vpn` (07:52:41), con `RESULTADO: todo correcto.` en cada uno.
3. OpenVPN (07:54:15):
   - Se copió `vpn/` con `P3_eice.sh zp-vpn-01 --copiar vpn` y se corrió `sudo bash vpn/P3_vpn_servidor.sh instalar` (VPN-01).
   - Después: `cliente trabajador01`, `cliente revocado01` y `revocar revocado01`.
   - `P5_hardening.sh aplicar` en `zp-vpn-01` (07:56).
4. Intranet (07:57:03): `allow 10.20.0.128/28;` agregado, `nginx -t` y `reload`. El respaldo quedó en `/etc/nginx/nginx.conf.antes-vpn`. Comprobado `vpn->intranet 200`.
5. `aplicar monitoreo` (07:58:16).
6. `aplicar acl-dmz` (08:00:48). Comprobado: EICE a `zp-web-01`, salida a Internet de `apt`, `https://zenite.dernait.com` 200 y `http` 301.
7. `aplicar acl-vpn` (08:05:14). Comprobado: EICE a `zp-vpn-01`, la Intranet 200, `apt` 200 y el servicio activo.
8. Hardening de `zp-web-01` y `zp-monitor-01` (08:08), con una sesión nueva de EICE después de cada uno.
9. Pruebas FW-02, FW-03, FW-06 y FW-07 (08:09–08:17). `zp-visitantes-01` se encendió solo para FW-07.
10. Cliente desde la Mac (14:46–14:48): VPN-02 a VPN-06.
11. `--validar` final (14:49:13) y apagado de todo. `P1_dmz_infra.sh --validar-apagado` (14:52:30) dio `RESULTADO: todo correcto.`

Para deshacer, de lo más reciente a lo más antiguo: `bash P3_firewall_final.sh --revertir acl-vpn`, `--revertir acl-dmz`, `--revertir monitoreo`, `--revertir vpn`, `--revertir base`. Cada paso quita solo lo que agregó P3; las reglas de EICE de P1 no se tocan nunca. Para la Intranet: `sudo cp -a /etc/nginx/nginx.conf.antes-vpn /etc/nginx/nginx.conf && sudo nginx -t && sudo systemctl reload nginx`.

### 4.3 Tabla final de reglas (Security Groups)

Los Security Groups guardan estado: la respuesta vuelve sola. "EICE" es el grupo `zenite-eice`.

| ID | Destino ← origen | Puerto | Dueño | Motivo |
|---|---|---|---|---|
| F-01 | `zenite-dmz` ← `0.0.0.0/0` | TCP 80 | P2 (`sgr-03d9b58c8ed70de85`), lo reconoce P3 | D10. Redirección a HTTPS y renovación de Let's Encrypt (HTTP-01) |
| F-02 | `zenite-dmz` ← `0.0.0.0/0` | TCP 443 | P2 (`sgr-0c9e35a5478b4aa05`), lo reconoce P3 | D10. Portal público |
| F-03 | `zenite-dmz` ← `zenite-ti` | TCP 22 | P3 | Administración desde TI |
| F-04 | `zenite-vpn` ← `0.0.0.0/0` | UDP 1194 | P3 | D10. VPN de trabajadores remotos |
| F-05 | `zenite-vpn` ← `zenite-ti` | TCP 22 | P3 | Administración desde TI |
| F-06 | `zenite-servidores` ← `zenite-vpn` | TCP 80 | P3 (lo pidió P2) | Intranet por la VPN (con NAT, el origen es `10.20.0.132`) |
| F-07 | dmz, vpn, servidores, ventas, visitantes, ti ← `zenite-ti` | UDP 161 | P3 (para P4) | SNMP solo desde el monitor (TI) |
| F-08 | dmz, vpn ← `zenite-ti` | ICMP | P3 (para P4) | Disponibilidad desde el monitor |
| P1 | dmz, vpn (y todos los `zp-*`) ← EICE | TCP 22 | P1 / P5 | Acceso administrativo; se conserva y se valida |

Sin reglas (y se valida que no aparezcan): `zenite-servidores` y `zenite-ti` ← `zenite-dmz`; `zenite-ti` ← `zenite-vpn`. La salida de los grupos queda abierta (lo aceptó P2): el control de salida de las subredes públicas lo hacen las ACL.

### 4.4 ACL nuevas (sin estado: cada ida tiene su retorno)

`acl-zenite-dmz` (`10.20.0.112/28`):

| Sentido | N.º | Regla | Motivo |
|---|---|---|---|
| Entrada | 100 | TCP 22 desde `10.20.0.144/28` (EICE) | Va **antes** de cualquier denegación |
| Entrada | 110 / 120 / 130 | TCP 22, UDP 161 e ICMP desde TI `10.20.0.96/28` | Administración y monitoreo |
| Entrada | **200** | **DENY todo desde `10.20.0.0/24`** | La DMZ no recibe nada del resto de la VPC |
| Entrada | 300 / 310 | TCP 80 y 443 desde `0.0.0.0/0` | Sitio público (D10) |
| Entrada | 320 / 330 | TCP y UDP 1024–65535 desde `0.0.0.0/0` | Retorno de `apt`, DNS y NTP que inicia la propia DMZ |
| Salida | 100 / 110 / 120 / 130 | Retorno efímero hacia EICE y TI; ICMP hacia TI | Respuestas a SSH y SNMP |
| Salida | **200** | **DENY todo hacia `10.20.0.0/24`** | La DMZ no inicia nada hacia Servidores ni TI |
| Salida | 300 / 310 | TCP 80 y 443 | `apt` y Let's Encrypt |
| Salida | 320 | TCP 1024–65535 | Respuestas a los visitantes del sitio |
| Salida | 330 / 340 / 350 | UDP y TCP 53, UDP 123 | DNS y NTP públicos (el DNS de Amazon y `169.254.169.123` no pasan por la ACL) |

`acl-zenite-vpn` (`10.20.0.128/28`) es igual, salvo:
- Entrada 140: TCP 1024–65535 desde Servidores `10.20.0.64/27`, para el retorno de la Intranet.
- Entrada 300: UDP 1194; 310 y 320: retornos TCP y UDP.
- Salida 140: TCP 80 hacia Servidores. Está **antes** del DENY 200; es el único camino de la VPN a la VPC.
- Salida 300: UDP 1024–65535, para las respuestas de OpenVPN a los clientes.

`acl-zenite-visitantes` (de P5) gana la entrada 130 (UDP 161 desde TI) y la salida 130 (UDP 1024–65535 hacia TI).

### 4.5 Qué cambió respecto de Fase 3 (a propósito)

- HARD-04 ("ninguna entrada desde `0.0.0.0/0`") pasa a tener **tres excepciones justificadas**: dmz 80, dmz 443 y vpn 1194. `--validar` comprueba que sean exactamente esas, en **todos** los grupos de la VPC.
- `P5_acls.sh --validar` marca ahora dos `[FALLA]` esperadas: `subnet-zenite-dmz` y `subnet-zenite-vpn` ya no están en la ACL predeterminada.
- `acl-zenite-visitantes` acepta SNMP desde TI.
- En `zp-intranet-01`, nginx acepta también `10.20.0.128/28`. El cambio es solo en la instancia: el archivo de Fase 3 del repositorio no se tocó.

## 5. Pruebas y evidencia

### 5.1 Resultados (filas para la matriz de P5)

| ID | Prueba | Esperado | Obtenido | Hora (UTC) | Estado | Evidencia |
|---|---|---|---|---|---|---|
| VPN-01 | Servicio OpenVPN activo y UDP 1194 en escucha | Activo | `openvpn-server@zenite` activo y habilitado, `0.0.0.0:1194`, `tun0 = 10.30.0.1/27`, NAT y cadenas correctas, `RESULTADO: todo correcto.` | 07:55 | Cumple | `FINAL_VPN-01_servicio.txt` |
| VPN-02 | El cliente conecta y recibe `10.30.0.x` | IP del pool | `utun6 inet 10.30.0.2`, ruta `10.20/24` por el túnel; el servidor lista `trabajador01=10.30.0.2` | 14:46:13 | Cumple | `FINAL_VPN-02_03_05_tunel.txt` |
| VPN-03 | Por la VPN se llega a la Intranet `10.20.0.71:80` | 200 | `HTTP/1.1 200 OK`, `Server: nginx`, 8456 bytes | 14:46:22 | Cumple | `FINAL_VPN-02_03_05_tunel.txt`, `FINAL_VPN-03_intranet_allow.txt` |
| VPN-04 | Sin VPN la Intranet no es accesible (mismo computador) | Sin respuesta | Sin `10.30.0.x` ni ruta `10.20`; `curl` da `intranet 000` (tiempo agotado) | 14:41:23 | Cumple | `FINAL_VPN-04_sin_vpn.txt` |
| VPN-05 | El cliente VPN no llega a TI (`10.20.0.102`) | Bloqueado | `10.20.0.102:22` sin respuesta; ping al 100 % de pérdida; también se bloquean `.71:22`, `.71:8080`, `.116:443` y `.132:22`. `zp-ti-01` estaba encendida como control | 14:46 | Cumple | `FINAL_VPN-02_03_05_tunel.txt` |
| VPN-06 | Un certificado revocado no conecta | Rechazado | `VERIFY ERROR: depth=0, error=certificate revoked: CN=revocado01` y `TLS handshake failed` | 14:47:53 | Cumple | `FINAL_VPN-06_revocado.txt` |
| FW-01 | Solo dmz 80/443 y vpn 1194 desde `0.0.0.0/0` | Exactas | `[OK] FW-01: las unicas entradas desde Internet son TCP 80 y 443 en zenite-dmz y UDP 1194 en zenite-vpn`; solo `zp-web-01` y `zp-vpn-01` tienen IP pública | 14:49:13 | Cumple | `FINAL_FW-01_aplicar_base.txt`, `FINAL_FW-01_validar_final.txt` |
| FW-02 | `zp-web-01` no alcanza Servidores ni TI (capa) | Bloqueado | `.71:80`, `.69:636`, `.102:22` y `.103:22` sin respuesta en 5 s. Lo bloquean la salida 200 de `acl-zenite-dmz` y los grupos `zenite-servidores` y `zenite-ti`. Control: `zp-vpn-01` sí llega a `.71:80` | 08:09:45 | Cumple | `FINAL_FW-02_aislamiento_dmz.txt` |
| FW-03 | Puerto 22 de las IP públicas cerrado | Sin respuesta | `18.210.66.163` y `3.228.84.176`: 22 y 8080 `Operation timed out`; 443 de la web `succeeded` | 08:13:21 | Cumple | `FINAL_FW-03_puertos_internet.txt` |
| FW-04 | EICE sigue funcionando hacia todas las instancias | Entra | Entró a las 7 instancias encendidas, también después de cada ACL y de cada hardening | 08:02–14:47 | Cumple | `FINAL_FW-04_acl_eice.txt`, `FINAL_FW-01_validar_final.txt` |
| FW-05 | SNMP 161 solo desde TI (desde Ventas falla) | Solo TI | Las reglas F-07 están aplicadas y validadas. La prueba real necesita `snmpd` (P4), que todavía no está instalado | — | **Pendiente (P4)** | — |
| FW-06 | Regresión SEG y HARD de Fase 3 | Igual, salvo los cambios intencionales | Grupos sin fallas; las ACL solo marcan DMZ y VPN (intencional). SEG-02 permitido; SEG-04 y SEG-05 bloqueados; HARD-02 (nmap) solo 22. HARD-03 correcto en todas. **Hallazgo:** `gssproxy` activo en Intranet y TI (ver 5.2) | 08:13–08:17 | Cumple con observación | `FINAL_FW-06_regresion_fase3.txt`, `FINAL_HARD_web_monitor.txt` |
| FW-07 | Visitantes sin acceso a la red interna ni a la DMZ por IP privada | Bloqueado | Desde `10.20.0.36`: `.116:443`, `.116:80`, `.71:80` y `.102:22` sin respuesta en 5 s. Lo bloquean `acl-zenite-visitantes` (200) y `acl-zenite-dmz` (entrada 200) | 08:11:03 | Cumple | `FINAL_FW-07_visitantes.txt` |

Capturas `.png` (las toma el humano en el ensayo, con la hora visible):
- `FINAL_VPN-02_cliente_conectado.png`: Terminal con `Initialization Sequence Completed` y `ifconfig utun` mostrando `10.30.0.x`.
- `FINAL_VPN-03_intranet_por_vpn.png`: navegador en `http://10.20.0.71/`.
- `FINAL_VPN-06_revocado.png`: el log del servidor con `certificate revoked`.
- `FINAL_FW-01_validar.png`: CloudShell (N. Virginia) con `RESULTADO: todo correcto.`

### 5.2 Fallos, correcciones y desviaciones

- **CRL con ruta relativa (prueba local en Docker, antes de AWS).** El servidor registraba `Failed to stat CRL file, not reloading CRL` y aceptaba un certificado revocado si se revocaba con el servicio en marcha. OpenVPN relee `crl-verify` en cada conexión, pero después de `user nobody` y desde otro directorio de trabajo. Se pasaron a **rutas absolutas** `ca`, `cert`, `key`, `tls-crypt` y `crl-verify`, y `--validar` lo comprueba. Repetida la prueba: `VERIFY ERROR ... certificate revoked`.
- **Error de sintaxis en `P3_firewall_final.sh`.** La expansión indirecta `${!$(reglas_acl ...)}` no es bash válido; la detectó `bash -n`. Se corrigió con una variable intermedia.
- **P2 abrió 80 y 443 antes de la autorización de P3** (ver la bitácora de P2). No se duplicaron ni se borraron: `base` las reconoce como F-01 y F-02, y `--validar` las acepta como D10.
- **Hardening de Fase 3 que no persiste: `gssproxy`.** Aparece activo en `zp-intranet-01` y `zp-ti-01` (Amazon Linux). Causa (en `zp-ti-01`): `is-enabled` da `disabled`, pero `WantedBy=auth-rpcgss-module.service` lo arranca en cada inicio, así que `disable --now` no basta. Corrección propuesta a P5: `systemctl mask gssproxy` en `P5_hardening.sh`. No abre puertos de red (`ss` muestra solo 22 y 80). P3 no lo cambió porque el script es de P5.
- **No repetidas:**
  - SEG-03 (Ventas → TI): `zp-ventas-01` estaba apagada; `zenite-ti` y `acl-zenite-ti` no cambiaron.
  - SEG-06 (Visitantes → Internet): necesita el NAT de P1, apagado por D12; la salida de Visitantes no cambió.
- **`P1_costos.sh`** no estaba en `Fase3/configuracion/`, sino en `FaseFinal/configuracion/`. Corrido desde allí (14:52:58) dio: 0 instancias, 0 NAT, 2 EIP asociadas, 0 EIP sin asociar y ningún recurso en otras regiones (`RESULTADO: sin hallazgos.`).
- La sesión de CloudShell se cerró por inactividad durante una pausa de unas 6 horas antes de las pruebas del cliente. No se perdió nada: el estado vive en `~/final-config/`. Las instancias siguieron encendidas en ese lapso (ver la sección 6).

## 6. Costos

| Concepto | Cálculo | Monto |
|---|---|---|
| Sesión del 2026-11-09 (instancias encendidas) | 4 t3.micro × ~6.8 h × US$0.0104 + 1 t3.small × ~6.7 h × US$0.0208 | **≈ US$0.42** (estimado; el usuario IAM no tiene `ce:GetCostAndUsage` y AWS factura con unas 24 h de retraso) |
| OpenVPN propia, 24/7 | t3.micro 730 h × US$0.0104 + EIP 730 h × US$0.005 | ≈ US$11.2 al mes, para hasta 10 clientes |
| AWS Client VPN (descartada) | US$0.10 por hora y por subred asociada + US$0.05 por hora y por conexión activa (página oficial, ejemplo de US East, consultada el 2026-11-09) | 1 subred 24/7 ≈ US$73 al mes **solo por la asociación**, más ≈ US$0.40 por trabajador por cada jornada de 8 h |

- Las 2 EIP (≈ US$0.12 por día cada una) se cobran también con las instancias apagadas. No se liberan (D12): el DNS depende de ellas.
- Al cerrar quedaron 0 instancias encendidas y 0 NAT.
- Client VPN se descarta porque cuesta unas 6 veces más al mes, también requiere certificados (autenticación mutua con ACM) y no cumple el objetivo de configurar el servicio nosotros. Su ventaja (servicio administrado y alta disponibilidad) no es necesaria para el prototipo.

## 7. Limitaciones y observaciones

- **FW-05 pendiente de P4.** Falta instalar `snmpd` en las instancias, aceptando solo `10.20.0.96/28`. Las reglas de red ya están.
- La **llave de la CA vive en `zp-vpn-01`** (modo 600, solo root). En producción, la CA estaría fuera de línea y el servidor solo tendría su certificado.
- La CRL vence el **2027-05-08**: hay que regenerarla (`easyrsa gen-crl`) antes de esa fecha, o la VPN rechazará a todos.
- Dentro de la VPC, la Intranet sigue en HTTP: el túnel cifra hasta `zp-vpn-01`. Para el prototipo es aceptable (está documentado en Fase 3).
- Con NAT, la Intranet ve a todos los clientes VPN como `10.20.0.132`. El registro por usuario queda en el log de OpenVPN (CN y hora), no en el de nginx.
- `acl-zenite-dmz` niega la VPC antes de 80 y 443. Desde Ventas o TI, el sitio público se abre **por su dominio** (sale por el NAT y entra con IP pública), no por la IP privada `10.20.0.116`.
- El `allow` de la Intranet está solo en la instancia. Si P2 reinstala la Intranet desde el repositorio, hay que agregar `allow 10.20.0.128/28;`.
- La autenticación LDAP de la VPN (opcional) no se hizo.

## 8. Documentación consultada

- OpenVPN 2.6, manual de referencia: https://openvpn.net/community-resources/reference-manual-for-openvpn-2-6/
- OpenVPN, guía (*HOWTO*): https://openvpn.net/community-resources/how-to/
- easy-rsa 3: https://github.com/OpenVPN/easy-rsa (README y `EasyRSA-Quickstart.md`)
- Amazon VPC, Security Groups: https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html
- Amazon VPC, Network ACL (orden de reglas y puertos efímeros): https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html
- EC2 Instance Connect Endpoint: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html
- AWS Client VPN: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html
- Precios de AWS VPN, incluido Client VPN (consultada el 2026-11-09): https://aws.amazon.com/vpn/pricing/

## 9. Archivos y evidencias de esta parte

- Configuración: `FaseFinal/configuracion/P3_firewall_final.sh`, `P3_eice.sh`, `vpn/P3_vpn_servidor.sh`, `vpn/zenite.conf`, `vpn/zenite-vpn-up.sh`, `vpn/.gitignore`.
- Evidencias: `FaseFinal/evidencias/03_vpn_firewall/FINAL_VPN-01..06_*.txt`, `FINAL_FW-01..07_*.txt` y `FINAL_HARD_web_monitor.txt`.
- Guion de la demo: `FaseFinal/reporte/P3_guion_demo.md`. Bitácora: `FaseFinal/bitacora/P3.md`.
