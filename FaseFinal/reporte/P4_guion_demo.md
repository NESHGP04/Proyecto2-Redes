# Guion de la demo · Persona 4 · LDAP (≈ 2 min) y SNMP/Grafana (≈ 3 min)

## Preparación (antes de salir a escena)

1. CloudShell en N. Virginia. Subir si hace falta: `P4_ldap_demo.sh`, `P3_eice.sh`, `P4_grafana_tunel.sh` no hace falta en CloudShell.
2. Encender solo lo necesario (6–8 vCPU; no las diez):

```bash
bash "$HOME/P1_instancias.sh" encender zp-ldap-01 zp-ventas-01 zp-ti-01 zp-monitor-01
aws ec2 wait instance-status-ok --region us-east-1 --instance-ids i-04f9cc2b9ee3f77cd i-0f3bd7b0615933e00 i-0378a8624df39958b i-00e786cb51a422c36
```

3. En Fedora: `aws login --profile zenite-ti --region us-east-1` (si la sesión caducó). Liberar puerto local 3000 si hay Docker.
4. Tener la contraseña de laboratorio de `ventas01` y la de Grafana `zeniteTI` solo en gestor/.env local (no en pantalla).

## LDAP (≈ 2 min)

| Paso | Qué se hace | Qué debe verse |
|---|---|---|
| 1 | Explicar en una frase: LDAPS con CA explícita; sin confiar en el cert falla | Contexto |
| 2 | EICE a Ventas: `bash "$HOME/P3_eice.sh" zp-ventas-01` y `bash "$HOME/P4_ldap_demo.sh" demo` | Prompt `zp-ventas-01`; bind OK; dos rechazos exit 49; tres búsquedas |
| 3 | (Opcional 20 s) Misma demo desde TI, o mostrar `demo_ti.png` / `FINAL_LDAP-R2_ti.txt` | Repetición R2 |
| 4 | Una frase sobre Visitantes bloqueado | Citar `FINAL_LDAP-05_*` si no hay tiempo de encender Visitantes |

## SNMP y Grafana (≈ 3 min)

| Paso | Qué se hace | Qué debe verse |
|---|---|---|
| 1 | En monitor (o CloudShell→EICE): `sudo -n bash "$HOME/P4_grafana.sh" --validar` | `[OK]` Grafana + paneles; 4 hosts up si están encendidos |
| 2 | Fedora: `bash FaseFinal/configuracion/P4_grafana_tunel.sh zenite-ti` | Mensaje de túnel; dejar terminal abierta |
| 3 | Navegador: `http://localhost:3000/d/zenite-snmp` con `zeniteTI` | ≥4 paneles con datos; hosts down visibles (GRAF-01/03) |
| 4 | Una frase: SNMP solo desde TI; Ventas no alcanza `:3000` | Citar GRAF-02 / SNMP-05; no abrir puertos |
| 5 | Ctrl+C al túnel | Túnel cerrado; monitor sigue encendido hasta el apagado |

## Plan B (evidencia guardada; decir fecha/origen)

| Si falla… | Mostrar |
|---|---|
| Demo LDAP en vivo | `FINAL_LDAP-04_ventas_bind.txt` + `demo.png` (11-nov-2026) |
| TI no arranca | `FINAL_LDAP-R2_ti.txt` + `demo_ti.png` |
| Grafana/túnel | `FINAL_GRAF-01_dashboard.png`, `FINAL_GRAF-03_caida.png`, `FINAL_GRAF-02_acceso.txt` |
| Recolector / scrapes | `FINAL_SNMP-02_cobertura_por_host.md` y un `FINAL_SNMP-01_*` |
| Aislamiento | `FINAL_SNMP-05_resumen.md` |

Identificar siempre el plan B como **evidencia de corrida anterior**, no como prueba en vivo.

## Al terminar

```bash
bash "$HOME/P1_instancias.sh" detener zp-ldap-01 zp-ventas-01 zp-ti-01 zp-monitor-01
```

No recrear NAT. Conservar la tabla con `Encendidas ahora: 0`.
