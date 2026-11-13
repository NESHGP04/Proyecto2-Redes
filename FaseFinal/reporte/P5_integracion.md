# Integración global, gobernanza de red y lecciones aprendidas

*Sección del reporte de la fase final · Persona 5 · proceso de consolidación de la infraestructura, marco de pruebas cruzadas, gestión de riesgos y lecciones de ingeniería.*

## 1. Objetivo de esta parte

- Integrar las contribuciones técnicas de los cuatro paquetes de trabajo especializados (Infraestructura y Costos de P1, Servicios Web y HTTPS de P2, VPN y Firewall de P3, y Monitoreo SNMP y LDAP de P4) en una arquitectura empresarial cohesionada, trazable y libre de discrepancias.
- Mantener la **Matriz Global de Pruebas** (`FaseFinal/reporte/matriz-de-pruebas.md`) garantizando el principio de honestidad técnica (regla R4), certificando resultados reales y gestionando la tabla de *Fallos y Acciones Correctivas*.
- Elaborar el **Reporte Maestro Consolidado** que documenta de principio a fin las cuatro fases del proyecto académico (Fase 1 Diseño, Fase 2 VPC, Fase 3 Servicios Internos y Fase Final Perimetral).
- Coordinar la higiene de seguridad del repositorio, verificando que ninguna credencial, llave privada SSH, llave de OpenVPN ni certificados sensibles se filtren al control de versiones.

---

## 2. Metodología de Integración y Reglas de Coordinación

La integración en un equipo de 5 personas requirió definir dependencias y protocolos de handoff estrictos:
1. **Handoff de Infraestructura Base (P1 → P2, P3, P4):** La Persona 1 aprovisionó las rutas hacia Internet Gateway (`rt-zenite-dmz` y `rt-zenite-vpn`), las dos Elastic IPs públicas (`18.210.66.163` y `3.228.84.176`) y las tres instancias Ubuntu 24.04 (`zp-web-01`, `zp-vpn-01`, `zp-monitor-01`), permitiendo que el resto del equipo iniciara configuraciones sobre identificadores certificados en CloudShell.
2. **Gobernanza Unificada del Firewall (P3):** Para evitar conflictos de reglas concurrentes, la Persona 3 asumió la titularidad exclusiva de las modificaciones de Security Groups y Network ACLs mediante `P3_firewall_final.sh`. Las aperturas necesarias para el portal web (TCP 80 y 443) y el monitoreo SNMP (UDP 161) fueron gestionadas mediante solicitudes formales de reglas.
3. **Cierre de Brechas de Fase 3 (P2 y P4):**
   - La Persona 2 ejecutó y certificó las pruebas `WEB-01` a `WEB-05` de la Intranet corporativa en `zp-intranet-01`, solventando la deuda de pruebas no registradas de la fase anterior.
   - La Persona 4 completó la recuperación y demostración robusta de OpenLDAP/LDAPS (`P4_ldap_demo.sh`, `LDAP-01..05` y `R1/R2`), desplegó agentes **SNMPv3 `authPriv` (SHA-256/AES)** en las 10 instancias con recolector **Prometheus 3.16.0 + `snmp_exporter` 0.31.0** (`SNMP-01..05`), cerró `FW-05` para P3 y entregó el componente extra de **Grafana OSS 13.3.0** (`GRAF-01..03`) accesible exclusivamente por TI vía túnel EICE.

---

## 3. Matriz de Pruebas de Integración de Extremo a Extremo (INT)

Para certificar que la red funciona como un ecosistema unificado de negocio y no como piezas aisladas, P5 definió 5 recorridos de integración (*End-to-End*):

| ID | Recorrido Evaluado | Pasos Técnicos Involucrados | Resultado Esperado | Resultado Real Certificado | Estado |
|---|---|---|---|---|:---:|
| **INT-01** | Coherencia Global de Infraestructura | Ejecución de `P5_validar_todo.sh` (solo lectura) | Todos los `--validar` de P1, P2 y P3 en `[OK]` | Coherencia total de rutas, Security Groups, DNS y certificados | **Por ejecutar** |
| **INT-02** | Recorrido de Cliente Externo | Navegador móvil en Internet LTE → `http://zenite.dernait.com` → Redirección 301 a HTTPS → Formulario de Cotización → Consulta de Código | Trámite registrado con código `ZP-` sin exponer datos internos | Completado en pruebas PUB-01 y PUB-02 (Código `ZP-22DW79PR` verificado) | **PASS** |
| **INT-03** | Recorrido de Teletrabajador Seguro | Cliente Mac en red externa → Túnel OpenVPN UDP 1194 → Asignación IP `10.30.0.2` → Consulta HTTP a Intranet `10.20.0.71` | Acceso fluido a la Intranet; bloqueo hacia TI (`10.20.0.102`) | Completado en pruebas VPN-02 y VPN-03 (HTTP 200 en Intranet; TI inaccesible) | **PASS** |
| **INT-04** | Recorrido de Auditoría y Soporte TI | Túnel EICE → `zp-monitor-01` (`127.0.0.1:3000`) → Consultas SNMPv3 / Grafana | Métricas de CPU, RAM, disco y red recolectadas por TI sin abrir puertos extra | Verificado en pruebas GRAF-01 y GRAF-02 desde estación de TI vía túnel EICE | **PASS** |
| **INT-05** | Ciclo de Vida y Cierre Financiero | Ejecución de `P1_dmz_infra.sh --validar-apagado` y `P1_costos.sh` | 0 instancias activas, 0 NAT activos, gasto en AWS inferior a US$15 | Verificado al cierre de sesión: 0 instancias, 0 NAT, consumo US$2.17 | **PASS** |

---

## 4. Gestión de Riesgos y Lecciones Aprendidas

1. **Persistencia de Servicios en Hardening del Sistema Operativo:**
   - *Riesgo:* La desactivación estándar mediante `systemctl disable` resultó insuficiente en Amazon Linux 2023 para demonios demandados por servicios del sistema (como `gssproxy` requerido por `auth-rpcgss-module.service`).
   - *Lección:* Para garantizar que el endurecimiento persista ante reinicios no programados, los demonios no deseados deben enmascararse (`systemctl mask --now`), bloqueando su enlace simbólico en systemd.
2. **Diseño de Rutas en OpenVPN y Privilegios del Demonio:**
   - *Riesgo:* El uso de rutas relativas para directivas críticas (`crl-verify crl.pem`) provocó fallos silenciosos cuando OpenVPN bajó sus privilegios al usuario sin privilegios `nobody`.
   - *Lección:* Todo servicio perimetral que ejecuta cambios de privilegios (*privilege dropping*) debe configurarse exclusivamente con rutas absolutas en sus archivos de configuración y scripts de arranque.
3. **Control Financiero en la Nube y Cuota de Cómputo:**
   - *Riesgo:* La acumulación inadvertida de costos por instancias encendidas o gateways administrados, así como el límite de cuota de **16 vCPU** en AWS al intentar validar 10 instancias simultáneamente.
   - *Lección:* El diseño de arquitecturas efímeras automatizadas (creación y destrucción bajo demanda del NAT Gateway) y el muestreo por tandas para monitoreo demostró que es posible desplegar una red empresarial completa manteniendo un costo de laboratorio controlado.
4. **Exposición Cero en Herramientas de Monitoreo:**
   - *Riesgo:* Publicar interfaces administrativas (Grafana `:3000`, Prometheus `:9090`) hacia la VPC o Internet amplía la superficie de ataque.
   - *Lección:* Vincular Grafana, Prometheus y `snmp_exporter` estrictamente a `127.0.0.1` y consumirlos mediante túnel SSH sobre **EICE** permite mantener el dashboard 100% operativo para TI sin abrir ningún puerto adicional en los Security Groups.

