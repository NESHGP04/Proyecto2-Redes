# Guion Oficial de Demostración en Vivo · Fase 3

**Curso:** CC3067 Redes, Semestre 2, 2026 – Sección 30  
**Proyecto:** Zenite Prestige Guatemala – Prototipo de Red en AWS  
**Duración Total Estimada:** 8 a 10 minutos  
**Modalidad de Conexión:** EC2 Instance Connect Endpoint (`eice-zenite-fase2`)  

---

## 1. Plan de Encendido y Lista de Verificación Previa (T − 30 min)

La demostración requiere que las instancias y el NAT Gateway estén operativos. Para operar con costo cero fuera de la presentación:

1. **Revisión de Billing (T − 30 min):** Verificar en la consola de AWS que no existan recursos huérfanos encendidos de sesiones anteriores.
2. **Verificar estado de partida:**
   ```bash
   bash Fase3/configuracion/P1_estado_inicial.sh
   ```
   *Debe reportar 0 instancias encendidas, 0 NAT Gateways y 0 Elastic IPs.*
3. **Creación del NAT Gateway (T − 25 min):**
   ```bash
   bash Fase3/configuracion/P1_gateways.sh crear
   ```
   *Tarda aprox. 2 minutos hasta que el NAT Gateway pase a estado `Available` y muestre `RESULTADO: todo correcto.`*
4. **Encendido de Instancias EC2 (T − 20 min):**
   ```bash
   bash Fase3/configuracion/P1_instancias.sh encender zp-ventas-01 zp-ti-01 zp-ntp-01 zp-ldap-01 zp-intranet-01 zp-visitantes-01
   ```
   *Esperar entre 3 y 5 minutos hasta que todas las instancias completen sus 3/3 status checks.*
5. **Comprobación de conectividad EICE:** Abrir una sesión rápida de terminal por EICE hacia `zp-ventas-01` y `zp-ldap-01`.
6. **Congelar cambios (T − 5 min):** No modificar Security Groups, tablas de rutas ni scripts en los minutos previos.
7. **Respaldo abierto:** Mantener abierta la carpeta `Fase3/evidencias/` con las capturas por si la consola experimenta latencia.

---

## 2. Desarrollo del Guion Paso a Paso

### Bloque 1: Topología de Red y Conectividad Externa NAT (P1 – Marinés) [~2 min]

* **Paso 1.1: Mostrar Internet Gateway y NAT Gateway en Consola AWS**
  - **Ubicación:** *VPC > Internet gateways*: mostrar `igw-zenite-fase3` en estado `Attached` a `vpc-zenite-fase2`.
  - **Ubicación:** *VPC > NAT gateways*: mostrar `nat-zenite-fase3` en `subnet-zenite-infra`, IP privada `10.20.0.148` y su Elastic IP pública (`3.95.121.55`).
* **Paso 1.2: Mostrar Tablas de Ruteo**
  - **Ubicación:** *VPC > Route tables*:
    - `rt-zenite-infra`: ruta `0.0.0.0/0` apuntando al Internet Gateway.
    - `rt-zenite-interna`: ruta `0.0.0.0/0` apuntando al NAT Gateway.
* **Paso 1.3: Demostración de Salida a Internet y 0 IPs Públicas**
  - En la consola EC2, mostrar que las 7 instancias tienen **únicamente IP privada** (sin IPv4 pública).
  - Conectar por EICE a `zp-ventas-01` y ejecutar:
    ```bash
    curl -sI https://aws.amazon.com | head -3
    curl -s https://checkip.amazonaws.com
    ```
  - **Explicación verbal:** *"La instancia privada no tiene IP pública, pero puede navegar a repositorios y servicios externos a través del NAT Gateway, saliendo identificada con la Elastic IP 3.95.121.55."*

---

### Bloque 2: Administración de Red: DHCP y Sincronización NTP (P2 – Camila) [~2 min]

* **Paso 2.1: Mostrar DHCP Option Set en Consola**
  - **Ubicación:** *VPC > DHCP option sets*: mostrar `dopt-zenite-fase3` asociado a `vpc-zenite-fase2`.
  - **Parámetros visibles:** `domain-name = zenite.internal`, `domain-name-servers = AmazonProvidedDNS`, `ntp-servers = 10.20.0.68`.
* **Paso 2.2: Verificación de Entrega DHCP en Clientes**
  - En la terminal de `zp-ventas-01`, ejecutar:
    ```bash
    networkctl status eth0 | grep -E "DNS|NTP|Search Domains"
    ```
  - **Explicación verbal:** *"El cliente obtiene automáticamente los parámetros de red corporativos sin intervención manual."*
* **Paso 2.3: Servidor y Clientes NTP con Chrony**
  - En la terminal de `zp-ntp-01` (`10.20.0.68`):
    ```bash
    chronyc sources -v
    chronyc clients
    ```
    *(Muestra la fuente Amazon Time Sync `169.254.169.123` stratum 3 y los clientes atendidos).*
  - En la terminal de `zp-ventas-01` / `zp-ti-01`:
    ```bash
    chronyc tracking
    ```
    *(Muestra sincronización stratum 5, Leap status Normal y offset en microsegundos).*
* **Paso 2.4: Aislamiento Horario de Visitantes**
  - En la terminal de `zp-visitantes-01`:
    ```bash
    chronyc sources
    ```
  - **Explicación verbal:** *"Visitantes recibe la opción DHCP pero Chrony queda en Reach 0 (Not synchronised) porque el Security Group de Servidores bloquea las peticiones UDP 123 desde la red de Visitantes."*

---

### Bloque 3: Directorio Activo y Autenticación OpenLDAP (P3 – Ernesto) [~2.5 min]

* **Paso 3.1: Salud del Servicio OpenLDAP**
  - En la terminal de `zp-ldap-01` (`10.20.0.69`, Ubuntu 24.04):
    ```bash
    bash Fase3/configuracion/ldap/P3_ldap.sh --validar
    sudo ss -tlnp | grep slapd
    ```
  - *(Muestra 8 comprobaciones en `[OK]` y el demonio escuchando en TCP 389 y TCP 636).*
* **Paso 3.2: Consulta de Directorio desde Ventas / TI**
  - En la terminal de `zp-ventas-01`:
    ```bash
    ldapsearch -x -LLL -H ldap://10.20.0.69 -b dc=zenite,dc=internal "(|(objectClass=posixAccount)(objectClass=posixGroup))" uid cn gidNumber memberUid
    ```
  - *(Retorna los grupos departamentales `ventas` y `ti`, y las 4 cuentas corporativas).*
* **Paso 3.3: Autenticación Cifrada en Tránsito (LDAPS 636)**
  - En la terminal de `zp-ventas-01`, ejecutar prueba de autenticación con contraseña correcta:
    ```bash
    LDAPTLS_CACERT=~/zenite-ldap.crt ldapwhoami -x -H ldaps://10.20.0.69 -D uid=ventas01,ou=People,dc=zenite,dc=internal -W
    ```
    *(Ingresar contraseña de laboratorio: responde `dn:uid=ventas01,ou=People,dc=zenite,dc=internal` con exit code 0).*
  - Repetir con contraseña errónea:
    *(Responde de inmediato `ldap_bind: Invalid credentials (49)`).*
* **Paso 3.4: Demostración de Bloqueo desde Visitantes**
  - En la terminal de `zp-visitantes-01`:
    ```bash
    ldapsearch -x -o nettimeout=5 -H ldap://10.20.0.69 -b dc=zenite,dc=internal "(uid=*)" uid
    ```
  - *(Anota timeout y finaliza con `Can't contact LDAP server (-1)`).*

---

### Bloque 4: Lógica de Negocio: Servidor Web Intranet (P4 – Juan Francisco) [~1.5 min]

* **Paso 4.1: Salud del Servidor Web en `zp-intranet-01`**
  - En la terminal de `zp-intranet-01` (`10.20.0.71`):
    ```bash
    systemctl is-active nginx
    curl -sI http://127.0.0.1/ | head -5
    ```
  - *(Muestra estado `active` y respuesta `HTTP/1.1 200 OK` con cabeceras de seguridad).*
* **Paso 4.2: Consulta HTTP Interna desde Ventas y TI (WEB-01 y WEB-02)**
  - En la terminal de `zp-ventas-01`:
    ```bash
    curl -sI http://10.20.0.71/ | head -5
    curl -s http://10.20.0.71/ | grep -i "<title>"
    ```
  - *(Muestra `HTTP/1.1 200 OK` y `<title>Zenite Prestige | Intranet</title>`).*
  - **Explicación verbal:** *"El personal corporativo de Ventas y TI tiene acceso inmediato al portal para consultar el inventario de vehículos de lujo, repuestos y citas de taller."*
* **Paso 4.3: Demostración de Bloqueo desde Visitantes (WEB-04)**
  - En la terminal de `zp-visitantes-01`:
    ```bash
    curl --connect-timeout 5 -I http://10.20.0.71/
    ```
  - *(El comando agota el tiempo de espera y finaliza con `Connection timed out` o código de error de red).*
  - **Explicación verbal:** *"La red de Visitantes está aislada tanto por el Security Group como por las directivas `allow/deny` de Nginx, impidiendo el acceso a la información confidencial de la empresa."*
* **Paso 4.4: Inaccesibilidad desde Internet (WEB-05)**
  - Mostrar en consola EC2 que `zp-intranet-01` no posee dirección IPv4 pública asignada ni balanceador de carga público, garantizando aislamiento perimetral.

---

### Bloque 5: Firewall, ACL y Hardening (P5 – Kevin) [~2 min]

* **Paso 5.1: Supremacía de Administración de TI (SEG-02)**
  - En la terminal de `zp-ti-01`:
    ```bash
    ping -c 2 10.20.0.10      # Ventas
    ping -c 2 10.20.0.68      # NTP / Servidores
    ping -c 2 10.20.0.36      # Visitantes
    ```
  - *(Muestra 0% de pérdida de paquetes hacia todas las subredes corporativas).*
* **Paso 5.2: Bloqueo Unidireccional hacia TI (SEG-03 y SEG-04)**
  - En la terminal de `zp-ventas-01`:
    ```bash
    ping -c 2 -W 2 10.20.0.102    # Intento hacia TI
    ssh -o ConnectTimeout=3 ec2-user@10.20.0.102
    ```
  - *(Muestra 100% packet loss y Connection timed out).*
  - En la terminal de `zp-ntp-01` (Servidores):
    ```bash
    ssh -o ConnectTimeout=3 ec2-user@10.20.0.102
    ```
  - *(Conexión bloqueada inmediatamente por Security Group y Network ACL).*
* **Paso 5.3: Aislamiento de Visitantes y Salida Externa (SEG-05 y SEG-06)**
  - En la terminal de `zp-visitantes-01`:
    ```bash
    ping -c 2 -W 2 10.20.0.10     # Intento hacia Ventas (bloqueado)
    ping -c 2 -W 2 10.20.0.68     # Intento hacia Servidores (bloqueado)
    curl -sI https://aws.amazon.com | head -3   # Salida a Internet (permitido vía NAT)
    ```
  - *(Demuestra el aislamiento estricto hacia la red privada y salida exitosa a Internet).*
* **Paso 5.4: Auditoría de Hardening y Cero Reglas 0.0.0.0/0 (HARD-02 y HARD-04)**
  - En la terminal de `zp-ti-01`, ejecutar escaneo de puertos:
    ```bash
    nmap -Pn -p 22,80,123,389,636 10.20.0.69 10.20.0.71 10.20.0.10
    ```
    *(Muestra puertos abiertos únicamente donde reside el servicio: 389/636 en LDAP, 80 en Intranet y Ventas filtered).*
  - En CloudShell, validar ausencia total de reglas públicas:
    ```bash
    bash Fase3/configuracion/P5_security_groups.sh --validar
    ```
    *(Muestra 0 reglas desde `0.0.0.0/0` y `Validacion completa sin fallos`).*

---

### Bloque 6: Cierre Financiero y Apagado Seguro [~30 seg]

Para demostrar la disciplina de costos ante el evaluador:

1. **Destruir el NAT Gateway:**
   ```bash
   bash Fase3/configuracion/P1_gateways.sh destruir
   ```
2. **Validar liberación de Elastic IP:**
   ```bash
   bash Fase3/configuracion/P1_gateways.sh --validar-apagado
   ```
3. **Detener todas las instancias EC2:**
   ```bash
   bash Fase3/configuracion/P1_instancias.sh detener
   ```
4. **Certificación de estado final:**
   ```bash
   bash Fase3/configuracion/P1_estado_inicial.sh
   ```
   *Debe confirmar 0 instancias activas, 0 NAT y 0 IPs públicas.*

---

## 3. Plan de Contingencia (Respaldos en Vivo)

Si la conexión a AWS CloudShell o la consola de AWS presenta latencia durante la presentación:

1. **Evidencias Gráficas de Respaldo:** Proyectar directamente las capturas certificadas en alta resolución ubicadas en:
   - `Fase3/evidencias/01_infra/FASE3_INF-01` a `INF-04`
   - `Fase3/evidencias/02_dhcp_ntp/FASE3_DHCP-01` a `03` y `FASE3_NTP-01` a `03`
   - `Fase3/evidencias/03_ldap/FASE3_LDAP-01` a `05` y `FASE3_LDAP-SG_reglas_zenite-servidores.png`
2. **Archivos de Salida de Texto:** Si una terminal tarda en responder, mostrar las salidas con timestamp y exit code guardadas en `Fase3/evidencias/03_ldap/*.txt`.
3. **JSONs de AWS:** Mostrar los volcados de configuración oficial en `Fase3/configuracion/*_encendido.json`.
