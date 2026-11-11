# Cobertura recibida de SNMP-02 por host

Diez hosts con las seis familias recibidas: uptime, CPU, RAM (`storage`), disco raíz, interfaces y procesos. Validación realizada sobre las salidas reales conservadas, no consultas propias a AWS.

La cuota obliga a usar tandas: **no acredita diez scrapes up simultáneos**. Los contadores CPU/red necesitan muestras separadas para calcular tasas; esta tabla acredita recepción de datos, no tasas estables. Las otras pruebas SNMP ya tienen evidencia; [el cierre del checkpoint 5](../../configuracion/P4_snmp_checkpoint5.md) está listo para revisión humana. P5 conserva la responsabilidad de incorporar la fila global.

| Host | Seis familias | UTC de la evidencia | Archivo |
|---|---|---|---|
| zp-monitor-01 | Recibidas | 11-nov-2026 05:11:32 | [Piloto](FINAL_SNMP-02_piloto_metricas.txt) |
| zp-ldap-01 | Recibidas | 11-nov-2026 05:11:32 | [Piloto](FINAL_SNMP-02_piloto_metricas.txt) |
| zp-ventas-01 | Recibidas | 11-nov-2026 05:36:16 | [Ventas](FINAL_SNMP-02_ventas_metricas.txt) |
| zp-ti-01 | Recibidas | 11-nov-2026 07:02:38–39 | [Primera tanda, fragmento](FINAL_SNMP-02_primera_tanda_fragmento.txt) |
| zp-ventas-02 | Recibidas | 11-nov-2026 07:02:39 | [Primera tanda, fragmento](FINAL_SNMP-02_primera_tanda_fragmento.txt) |
| zp-ntp-01 | Recibidas | 11-nov-2026 07:02:39 | [Primera tanda, fragmento](FINAL_SNMP-02_primera_tanda_fragmento.txt) |
| zp-intranet-01 | Recibidas | 11-nov-2026 07:02:39 | [Primera tanda, fragmento](FINAL_SNMP-02_primera_tanda_fragmento.txt) |
| zp-visitantes-01 | Recibidas | 11-nov-2026 07:02:39 | [Primera tanda, fragmento](FINAL_SNMP-02_primera_tanda_fragmento.txt) |
| zp-web-01 | Recibidas | 11-nov-2026 07:56:41 | [Web/VPN sin NAT](FINAL_SNMP-02_web_vpn_sin_nat.txt) |
| zp-vpn-01 | Recibidas | 11-nov-2026 07:56:41–42 | [Web/VPN sin NAT](FINAL_SNMP-02_web_vpn_sin_nat.txt) |

El fragmento de primera tanda empieza a mitad de Ventas-01; las seis familias de los otros cinco hosts sí están completas. Para monitor/LDAP/Ventas se usan las corridas anteriores completas, sin reconstruir la parte ausente.

En [la segunda tanda](FINAL_SNMP_recolector_segunda_tanda.txt), 07:56:42 UTC, ocho scrapes up y Ventas-02/Visitantes down después de sus paradas EC2 explícitas. La [recuperación posterior de Ventas-02](FINAL_SNMP-04_ventas02_recuperacion.txt) quedó acreditada a las 08:39:16 UTC: ocho up y Visitantes/VPN down, coherentes con sus paradas. Las [pruebas de origen](FINAL_SNMP-05_resumen.md) también están documentadas. No se afirma diez up simultáneos.
