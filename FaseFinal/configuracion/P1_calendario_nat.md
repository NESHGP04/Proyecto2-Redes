# Calendario del NAT Gateway · fase final (propuesta de P1, por confirmar)

El NAT se crea solo cuando alguien necesita Internet en una instancia **privada** y se destruye al terminar. La web (`zp-web-01`) y la VPN (`zp-vpn-01`) **no** lo necesitan: salen por su Elastic IP.

## Quién necesita Internet en instancias privadas

| Persona | Para qué | Subredes / instancias |
|---|---|---|
| P4 | Instalar Grafana y agentes SNMP; diagnosticar LDAP | `zp-monitor-01` (TI), `zp-ldap-01` (Servidores) y las que lleven agente SNMP (Ventas, Visitantes, TI) |
| P2 | Paquetes de la Intranet si falta algo (WEB-01..05) | `zp-intranet-01` (Servidores) |
| P3 | Normalmente nada (la VPN sale por su Elastic IP); pruebas de regresión de Fase 3 | Ventas, Visitantes |

**Subred TI:** no tiene Internet por su ACL. Para instalar en `zp-monitor-01` hay que revertir temporalmente `P5_acls.sh --revertir` (**lo ejecuta P3**) y volver a aplicar las ACL al terminar. P1 solo coordina.

## Ventanas propuestas (hora de Guatemala, UTC−6)

| Ventana | Día | Horario | Para | Confirmado por |
|---|---|---|---|---|
| A | Vie 6 nov | 19:00–21:00 | P4: Grafana y SNMP en el monitor; diagnóstico de LDAP. P3 revierte la ACL de TI antes de empezar | |
| B | Sáb 7 nov | 09:00–11:00 | P4: agentes SNMP en las demás instancias. P2: paquetes de la Intranet si faltan | |
| C | Sáb 7 nov | 15:00–17:00 | Reserva: lo que no haya terminado | |
| D | Dom 8 nov | 10:00–12:00 | Reserva final de instalaciones, ya con el dominio y HTTPS en marcha | |
| — | Lun 9 nov | sin NAT | Congelamiento a las 18:00 y ensayo; todo debe estar instalado | |
| — | Mar 10 nov | sin NAT | Demo | |

## Cómo se pide y se usa

1. La persona avisa en el grupo con **15 minutos de anticipación**: qué instancia, para qué y cuánto tiempo (máximo 3 h).
2. P1 crea el NAT: `bash P1_gateways.sh crear` (tarda unos 2 minutos en pasar a `available`).
3. La persona instala lo que necesita y avisa en el grupo cuando termina.
4. P1 lo destruye: `bash P1_gateways.sh destruir`, y confirma con `bash P1_dmz_infra.sh --validar-apagado` (debe dar 0 NAT) y `bash P1_costos.sh`.

## Costo

- NAT ≈ US$0.045/h + su IPv4 ≈ US$0.005/h = **≈ US$0.10 por ventana de 2 h**. Las cuatro ventanas suman unos US$0.40 más el tráfico.
- El riesgo real es **olvidarlo encendido**: ≈ US$1.20 por día. Por eso se destruye al terminar cada ventana y se revisa con `P1_costos.sh`.

## Avisos

- `bash P1_gateways.sh --validar` y `--validar-apagado` (Fase 3) marcarán dos `[FALLA]` esperadas: la ruta por defecto de `rt-zenite-dmz` y el conteo de Elastic IP. Se ignoran; el cierre válido es `P1_dmz_infra.sh --validar-apagado`.
- `P1_gateways.sh destruir` libera solo la Elastic IP del NAT (`eip-nat-zenite-fase3`), no las de la web ni la VPN.
- Cada NAT nuevo estrena IP pública: no afecta a nada, porque la web y la VPN usan sus propias Elastic IP.
