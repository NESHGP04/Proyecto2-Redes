# Presentación Ejecutiva de Avances · Fase 3

**Curso:** CC3067 Redes, UVG – Semestre 2, 2026 (Sección 30)  
**Proyecto:** Zenite Prestige Guatemala – Servicios de Red y Seguridad en AWS  
**Identidad Visual del Equipo:**  
- **Color Principal:** Azul Marino Corporativo (`#14213D`)  
- **Color Secundario / Acentos:** Dorado Zenite (`#C9A227`)  
- **Tipografías:** Títulos en **Georgia**, Cuerpo de texto en **Calibri**  

---

## Diapositiva 1: Portada

- **Título:** Zenite Prestige Guatemala: Servicios de Red y Seguridad en la Nube
- **Subtítulo:** Proyecto Final – Fase 3 (CC3067 Redes, Sección 30)
- **Integrantes:**
  - Camila Richter 23183 (P2 – DHCP y NTP)
  - Carlos Alburez 231311 (P6 – Integración, Reporte y Demo)
  - Ernesto Ascencio 23009 (P3 – LDAP)
  - Juan Francisco Martínez 23617 (P4 – Intranet Web)
  - Kevin Villagrán 23584 (P5 – Seguridad, Firewall, ACL y Hardening)
  - Marinés García 23391 (P1 – Infraestructura AWS y Costos)
- **Catedrático:** Ing. Juan Carlos Canteo · Octubre de 2026

---

## Diapositiva 2: Objetivos y Alcance de la Fase 3

- **Propósito:** Desplegar servicios corporativos de administración, lógica de negocio y seguridad perimetral sobre la VPC de Fase 2 (`10.20.0.0/24`).
- **Servicios Centrales:**
  - Administración de red automatizada: **DHCP** y sincronización de hora **NTP**.
  - Directorio corporativo y autenticación centralizada: **OpenLDAP / LDAPS (636)**.
  - Lógica de negocio interna: Servidor web **Intranet** (Nginx en HTTP 80).
- **Seguridad y Perímetro:**
  - Salida a Internet controlada mediante **Internet Gateway** y **NAT Gateway**.
  - **Defensa en Profundidad:** Security Groups (stateful) + Network ACLs (stateless).
  - Acceso administrativo seguro mediante **EC2 Instance Connect Endpoint (EICE)** con **0 direcciones IPv4 públicas**.
  - **Hardening** riguroso en las 7 instancias de la red.

---

## Diapositiva 3: Infraestructura Base y Topología de Red (P1)

- **VPC Base:** `vpc-zenite-fase2` (`vpc-0e4c1d0b2314ab4df`) en `us-east-1a`.
- **Gateways y Conectividad Externa:**
  - Internet Gateway: `igw-zenite-fase3` (`Attached`).
  - NAT Gateway: `nat-zenite-fase3` (`10.20.0.148` en `subnet-zenite-infra`, Elastic IP `3.95.121.55`).
- **Tablas de Rutas:**
  - `rt-zenite-infra`: `0.0.0.0/0` → IGW.
  - `rt-zenite-interna`: `0.0.0.0/0` → NAT Gateway (tráfico de salida traducido).
- **Inventario Total:** 7 instancias EC2 (`t3.micro`) sin direcciones públicas asignadas.

---

## Diapositiva 4: Administración de Red: DHCP y Sincronización NTP (P2)

- **DHCP Option Set (`dopt-zenite-fase3`):**
  - Dominio: `zenite.internal`.
  - Servidores DNS: `AmazonProvidedDNS`.
  - Servidor NTP: `10.20.0.68` (`zp-ntp-01`).
- **Sincronización Horaria con Chrony:**
  - Servidor `zp-ntp-01` sincronizado con Amazon Time Sync (`169.254.169.123`) en stratum 3.
  - Clientes corporativos (Ventas y TI) toman la opción DHCP automáticamente (`/run/chrony.d`) y sincronizan en stratum 5 con offsets menores a 4 microsegundos.
  - **Aislamiento verificado:** La red de Visitantes recibe la opción DHCP pero queda sin sincronizar (`Reach 0`) debido a que el firewall bloquea peticiones hacia Servidores.

---

## Diapositiva 5: Autenticación Centralizada: OpenLDAP (P3)

- **Servidor Host:** `zp-ldap-01` (`10.20.0.69`, Ubuntu 24.04 LTS).
- **Estructura Organizacional:**
  - Base DN: `dc=zenite,dc=internal`.
  - Unidades Organizacionales: `ou=People` y `ou=Groups`.
  - Grupos: `cn=ventas` (GID 10001) y `cn=ti` (GID 10002).
  - Cuentas corporativas: `ventas01`, `ventas02`, `ti01`, `ti02` con atributos POSIX.
- **Cifrado en Tránsito (LDAPS 636):**
  - Certificado X.509 autofirmado con SAN `IP:10.20.0.69`.
  - Autenticación `bind` obligatoria por puerto seguro 636.
  - Cero contraseñas en Git: hashes criptográficos `{SSHA}` con sal individual inyectados desde `.env`.

---

## Diapositiva 6: Lógica de Negocio: Portal Web Intranet (P4)

- **Servidor Web:** Nginx 1.30.5 sobre `zp-intranet-01` (`10.20.0.71`) en HTTP 80.
- **Contenido Corporativo:**
  - Catálogo exclusivo de vehículos de lujo (Mercedes-Benz, BMW, Porsche).
  - Inventario de repuestos y agenda de turnos de taller mecánico.
  - Recursos 100% locales (sin dependencias de CDNs externas).
- **Seguridad en la Capa Web:**
  - Directivas de origen en Nginx: `allow` solo para localhost, Ventas, TI y Servidores; `deny all` para los demás.
  - Cabeceras HTTP seguras: CSP estricta, `X-Content-Type-Options: nosniff` y `server_tokens off`.

---

## Diapositiva 7: Defensa en Profundidad, ACL y Hardening (P5)

- **Estrategia Multinivel:**
  - **Security Groups (Stateful):** Control granular a nivel de interfaz ENI por grupos de origen. Cero reglas de ingreso desde `0.0.0.0/0`.
  - **Network ACLs Dedicadas (Stateless):**
    - `acl-zenite-visitantes`: Regla 200 DENY hacia `10.20.0.0/24`; salida permitida exclusivamente a Internet vía NAT.
    - `acl-zenite-ti`: Administración libre hacia la red corporativa; sin salida hacia Internet.
- **Auditoría y Hardening de Host:**
  - Escaneo `nmap` desde TI certifica únicamente puertos requeridos abiertos.
  - OpenSSH asegurado en las 7 instancias (`PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3`).
  - Servicios prescindibles deshabilitados en Amazon Linux y Ubuntu.

---

## Diapositiva 8: Matriz de Pruebas: Resultados de Validación

- **28 Casos de Prueba Ejecutados:**
  - **Infraestructura (INF-01 a 04):** 4/4 PASS.
  - **DHCP y NTP (DHCP-01 a 03, NTP-01 a 03):** 6/6 PASS.
  - **LDAP (LDAP-01 a 05):** 5/5 PASS (1 fallo de SG corregido: `LDAP-02`).
  - **Intranet Web (WEB-01 a 05):** 5/5 PASS (1 fallo inicial de publicación resuelto).
  - **Seguridad y ACL (SEG-01 a 06):** 6/6 PASS (1 fallo de permisos IAM corregido: `SEG-01`).
  - **Hardening (HARD-01 a 04):** 4/4 PASS (1 fallo de script en Ubuntu corregido: `HARD-03`).
- **Resumen:** **100 % de Pruebas Aprobadas (28 de 28)**, demostrando total trazabilidad entre teoría y evidencia de AWS.

---

## Diapositiva 9: Control Presupuestario y Gestión de Costos

- **Estrategia Financiera en la Nube:**
  - Instancias EC2 `t3.micro`: se mantienen detenidas fuera de las ventanas de desarrollo.
  - NAT Gateway (recurso de costo horario): creado al inicio de cada sesión y destruido liberando la Elastic IP inmediatamente al terminar.
- **Consumo Real Incurrido:**
  - Sesiones acumuladas de P1, P2, P3, P4 y P5: menos de 2 horas totales de NAT Gateway activo.
  - Gasto financiero total inferior a **USD 0.20**, conservando la totalidad de los créditos asignados.

---

## Diapositiva 10: Conclusiones y Demostración en Vivo

- **Conclusiones Clave:**
  1. Integración fluida entre servicios nativos de AWS y demonios Linux estándar.
  2. Efectividad comprobada del modelo de Defensa en Profundidad (SG + NACL).
  3. Cero superficie pública y administración segura por túneles efímeros EICE.
  4. Disciplina de costos como pilar de ingeniería en la nube.
- **Paso a la Demostración en Vivo:**
  - Conexión por EC2 Instance Connect Endpoint.
  - Validación de DHCP, NTP, consultas LDAP, navegación en Intranet y aislamiento de Visitantes.
