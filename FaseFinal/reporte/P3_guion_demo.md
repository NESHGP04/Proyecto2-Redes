# Guion de la demo · Persona 3 · VPN (≈ 3 min) y firewall (≈ 2 min)

Preparación (10 min antes):
1. Encender `zp-vpn-01`, `zp-intranet-01` y `zp-ti-01` (control de VPN-05):
   `bash ../../Fase3/configuracion/P1_instancias.sh encender zp-vpn-01 zp-intranet-01 zp-ti-01`
2. En CloudShell (N. Virginia), dentro de `~/Proyecto2-Redes/FaseFinal/configuracion`, correr `bash P3_eice.sh zp-vpn-01 true` para comprobar EICE.
3. En la Mac, dejar abiertas dos ventanas de Terminal y el navegador. El perfil está en `~/zenite-vpn/` (no se muestra su contenido).

## VPN (≈ 3 min)

| Paso | Qué se hace | Qué debe verse |
|---|---|---|
| 1 | Sin VPN: `curl -m 5 http://10.20.0.71/` | Tiempo agotado (VPN-04): la Intranet es privada |
| 2 | `sudo /opt/homebrew/sbin/openvpn --config ~/zenite-vpn/trabajador01.ovpn` | `Initialization Sequence Completed` |
| 3 | `ifconfig \| grep 10.30.0` | `inet 10.30.0.x` (VPN-02) |
| 4 | Navegador: `http://10.20.0.71/` | La Intranet (VPN-03) |
| 5 | `nc -vz -G 5 10.20.0.102 22` | `Operation timed out`: el perfil es solo Intranet y nunca llega a TI (VPN-05) |
| 6 | Explicar en una frase | Certificados de una CA propia, `tls-crypt`, NAT en el servidor, *split tunnel* (Internet del trabajador sale por su casa) |
| 7 | Ctrl+C, luego `sudo /opt/homebrew/sbin/openvpn --config ~/zenite-vpn/revocado01.ovpn` | Nunca conecta. En CloudShell: `bash P3_eice.sh zp-vpn-01 'sudo journalctl -u openvpn-server@zenite -n 20 \| grep revoked'` muestra `certificate revoked` (VPN-06) |

## Firewall (≈ 2 min)

| Paso | Qué se hace | Qué debe verse |
|---|---|---|
| 1 | CloudShell: `bash P3_firewall_final.sh --validar \| tail -25` | Las únicas entradas desde Internet son 80 y 443 (web) y 1194 (VPN). Solo web y VPN tienen IP pública. EICE correcto. `RESULTADO: todo correcto.` (FW-01, FW-04) |
| 2 | Mac: `nc -vz -G 5 3.228.84.176 22` | Tiempo agotado: SSH solo entra por EICE (FW-03) |
| 3 | Mostrar en la consola la ACL `acl-zenite-dmz`, entradas 100 → 200 → 300 | EICE primero; la regla 200 niega la VPC; después 80 y 443 desde Internet. La DMZ queda aislada (FW-02) |

## Plan B

- **La VPN no conecta** (red de la universidad bloquea UDP 1194, o la instancia no arrancó): mostrar `FINAL_VPN-02_03_05_tunel.txt` y `FINAL_VPN-06_revocado.txt`. En vivo, correr `bash P3_eice.sh zp-vpn-01 'sudo bash vpn/P3_vpn_servidor.sh --validar'` (VPN-01) y compartir datos desde el celular para el paso 2.
- **CloudShell lento o caído:** mostrar `FINAL_FW-01_validar_final.txt` y la tabla de reglas del reporte (sección 4.3).
- **Al terminar:** `bash ../../Fase3/configuracion/P1_instancias.sh detener zp-vpn-01 zp-intranet-01 zp-ti-01` y `bash P1_dmz_infra.sh --validar-apagado`.
