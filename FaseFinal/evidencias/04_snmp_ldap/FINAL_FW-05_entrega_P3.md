# Entrega para P3 · FW-05

**Resultado comprobado:** desde zp-monitor-01 responde SNMPv3 en zp-ldap-01; desde zp-ventas-01 se agota el tiempo con sus credenciales válidas instaladas. Dos controles del monitor, anterior y posterior, respondieron con exit 0.

| Origen → destino | Obtenido | UTC 11-nov-2026 | Guatemala 11-nov-2026 |
|---|---|---|---|
| Monitor → LDAP | snmpwalk autenticado, exit 0 | 08:02:25 | 02:02:25 |
| Ventas-01 → LDAP | Sin respuesta, exit 1 | 08:02:31–33 | 02:02:31–33 |
| Monitor → LDAP | snmpwalk autenticado, exit 0 | 08:02:39 | 02:02:39 |

Estado propuesto para **FW-05 de P3: PASS**, con alcance de estos orígenes/destino y su correlación. Evidencia: [transcripción recibida](FINAL_FW-05_ventas_controles.txt). La captura queda por aportar/verificar; esta transcripción no se presenta como imagen.

La ACL TI ya estaba restaurada y el NAT eliminado. No se cambiaron reglas para la prueba, no se editó la matriz de P5 ni se enviaron mensajes a P3. El humano entrega este archivo y P3 cierra su fila. SNMP-05 de P4 aún requiere Visitantes y prueba exterior.
