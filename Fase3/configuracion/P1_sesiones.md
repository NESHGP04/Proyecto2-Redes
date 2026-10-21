# Fase 3 – Cómo encender y apagar el NAT y las instancias

El **NAT Gateway** (la salida a Internet de las instancias privadas) cobra por hora (≈ US$0.05 por hora, ≈ US$1.20 por día), y la cuenta no tiene
créditos. Por eso **no está encendido de forma permanente**: quien necesite Internet lo enciende, y quien termine y vea que nadie más lo usa lo apaga.
Las instancias también se encienden solo mientras se trabaja. Todo se hace en **AWS CloudShell** (región N. Virginia) con estos scripts de
`Fase3/configuracion/`. Súbelos con *Actions → Upload file*.

Necesitas permisos de EC2 en tu usuario IAM (política `fase3-red`, que da la dueña de la cuenta). Si un comando dice `UnauthorizedOperation`, pídesela.

## Al empezar a trabajar

1. ¿Ya hay NAT? (solo lectura)
   ```text
   bash P1_gateways.sh --validar
   ```
   - Si dice `[OK]` en todo: ya está encendido (alguien lo está usando). Anota en el grupo que lo vas a usar.
   - Si el NAT "no existe" y necesitas Internet (instalar paquetes, `curl` a Internet): enciéndelo.
     ```text
     bash P1_gateways.sh crear
     ```
     Muestra el plan, pide escribir `si` y tarda de 1 a 3 minutos. Debe terminar en `RESULTADO: todo correcto.`
2. Enciende **solo tus instancias** (nombres `zp-*`; sin nombres enciende todas):
   ```text
   bash P1_instancias.sh encender zp-ntp-01 zp-ventas-01
   ```
   Espera de 3 a 5 minutos (status checks 2/2) y conéctate: consola → instancia → *Connect → EC2 Instance Connect → Connect using EC2 Instance
   Connect Endpoint* → `eice-zenite-fase2`. Usuario: `ec2-user` (en `zp-ldap-01`, que es Ubuntu: `ubuntu`).

## Al terminar

1. Detén tus instancias:
   ```text
   bash P1_instancias.sh detener zp-ntp-01 zp-ventas-01
   ```
2. **¿Nadie más usa Internet?** Pregunta en el grupo. Si nadie lo necesita, apaga el NAT:
   ```text
   bash P1_gateways.sh destruir
   ```
   Antes de pedir confirmación muestra **quién lo creó y hace cuánto**. Si no eres quien lo encendió y no avisaste, no lo destruyas sin preguntar.
3. Comprueba que no quedó nada con costo:
   ```text
   bash P1_gateways.sh --validar-apagado
   bash P1_instancias.sh --validar
   ```

## Reglas

- Los scripts piden confirmación (`si`) antes de crear o destruir. No los edites; si algo falla, copia el mensaje completo y avisa a la Persona 1.
- El **Internet Gateway** se queda siempre (no cobra). Solo el NAT y su Elastic IP se crean y se destruyen.
- Un NAT encendido más de 8 horas muestra un aviso en `--validar`. Revisa que no se haya quedado olvidado.
- Los discos de las instancias cuestan aunque estén apagadas (≈ US$0.64 al mes cada uno); es poco, pero no crees instancias de más.
- Nunca des IP pública a una instancia ni abras puertos a `0.0.0.0/0`.
- El estado de los recursos con costo se puede ver en cualquier momento con `bash P1_estado_inicial.sh` (solo lectura).
