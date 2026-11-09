#!/bin/sh
# zenite-vpn-up.sh - lo ejecuta OpenVPN (directiva up, todavia como root) al levantar el tunel. Idempotente.
# NAT: los clientes 10.30.0.0/27 salen hacia la VPC con la IP de zp-vpn-01 (10.20.0.132), decision D7.
# Perfil "solo Intranet": desde el tunel solo se reenvia TCP 80 hacia zp-intranet-01 (10.20.0.71); TI (10.20.0.96/28) nunca.
# Hacia el propio servidor, desde el tunel solo se acepta ICMP.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
set -e
sysctl -qw net.ipv4.ip_forward=1 || echo "zenite-vpn-up: no se pudo activar ip_forward (revisar /etc/sysctl.d/99-zenite-vpn.conf)" >&2
for C in ZENITE-VPN-FWD ZENITE-VPN-IN; do iptables -N "$C" 2>/dev/null || iptables -F "$C"; done
iptables -A ZENITE-VPN-FWD -d 10.20.0.96/28 -j DROP
iptables -A ZENITE-VPN-FWD -d 10.20.0.71/32 -p tcp --dport 80 -j ACCEPT
iptables -A ZENITE-VPN-FWD -j DROP
iptables -A ZENITE-VPN-IN -p icmp -j ACCEPT
iptables -A ZENITE-VPN-IN -j DROP
iptables -C FORWARD -i tun+ -j ZENITE-VPN-FWD 2>/dev/null || iptables -I FORWARD 1 -i tun+ -j ZENITE-VPN-FWD
iptables -C INPUT -i tun+ -j ZENITE-VPN-IN 2>/dev/null || iptables -I INPUT 1 -i tun+ -j ZENITE-VPN-IN
iptables -t nat -C POSTROUTING -s 10.30.0.0/27 -d 10.20.0.0/24 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 10.30.0.0/27 -d 10.20.0.0/24 -j MASQUERADE
