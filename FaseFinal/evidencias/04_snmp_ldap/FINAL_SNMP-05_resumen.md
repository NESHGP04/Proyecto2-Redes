# SNMP-05 · Restricción de orígenes

**Resultado propuesto: PASS**, con las consultas y controles reales recibidos del 11-nov-2026. No se modificaron filtros para producir la evidencia. Correlacionado con diagnóstico AWS de las 07:50:19–27 UTC: seis SG restringen UDP 161 a TI y las ACL permiten las consultas/retornos previstos.

| Origen → destino | Resultado | UTC | Guatemala | Evidencia |
|---|---|---|---|---|
| Ventas-01 → LDAP | Timeout, exit 1; controles autenticados del monitor antes/después exit 0 | 08:02:25–39 | 02:02:25–39 | [FW-05](FINAL_FW-05_ventas_controles.txt) |
| CloudShell → EIP VPN | Timeout, exit 1; controles del monitor antes/después exit 0 con las mismas claves | 08:22:14; controles 08:22:12/28 | 02:22:14; controles 02:22:12/28 | [Exterior](FINAL_SNMP-05_internet_web_vpn.txt) |
| CloudShell → EIP Web | Timeout, exit 1; controles del monitor antes/después exit 0 con las mismas claves | 08:22:16; controles 08:22:06/22 | 02:22:16; controles 02:22:06/22 | [Exterior](FINAL_SNMP-05_internet_web_vpn.txt) |
| Visitantes → LDAP | Timeout, exit 1; controles autenticados del monitor antes/después exit 0 | 08:29:21–34 | 02:29:21–34 | [Visitantes](FINAL_SNMP-05_visitantes_controles.txt) |

Los intentos desde Ventas/Visitantes usaron sus credenciales instaladas; el guion exterior usó las mismas claves en las consultas públicas y en sus cuatro controles privados. Una clave errónea no se usó como evidencia de aislamiento.

Alcance: sin datos SNMP desde esos orígenes/destinos en esos intervalos. Los controles reducen la ambigüedad de un agente caído. Un timeout UDP no identifica por sí solo qué dispositivo descarta ni demuestra todos los posibles orígenes de Internet. Las dos EIP públicas son las autorizadas de Web/VPN. No se publica la IP de salida de CloudShell.

La limpieza de las copias del guion exterior quedó confirmada a las 08:22:33 UTC. La ausencia del archivo temporal del rescate anterior quedó comprobada por lectura a las 08:39:37 UTC en [la salida de recuperación](FINAL_SNMP-04_ventas02_recuperacion.txt); no se reconstruyen otros pasos del rescate cuya salida no se recibió. Capturas gráficas de estas pruebas por aportar/verificar; las transcripciones son evidencia textual.

P4 prepara la entrega; no se editó la matriz global de P5 ni se enviaron mensajes. Para FW-05 de P3 está preparado [el archivo de entrega](FINAL_FW-05_entrega_P3.md).
