# Proyecto2-Redes
Proyecto 2 - Redes

## Fase 2 – Instancias de prueba (MD_4) y pruebas de conectividad (MD_5)

Lo que se hizo, en orden. Los detalles están en [Fase2/README.md](Fase2/README.md) (parte 4), en la
[bitácora](Fase2/bitacora.md) y en las secciones del reporte
[04_instancias_de_prueba.md](Fase2/reporte/04_instancias_de_prueba.md) y
[05_pruebas_de_conectividad.md](Fase2/reporte/05_pruebas_de_conectividad.md).

1. **Acceso a AWS sin Access Keys.** El usuario IAM `Ernesto` recibió de la dueña de la cuenta la política
   `SignInLocalDevelopmentAccess` y una política inline con `ec2:Describe*`, `ec2:RunInstances`, `ec2:CreateTags`,
   `ec2:Start/Stop/TerminateInstances`, `ec2-instance-connect:OpenTunnel` y `ec2-instance-connect:SendSSHPublicKey`.
2. **AWS CLI en la Mac** (versión 2.32 o superior) e inicio de sesión con el usuario de consola:
   ```bash
   brew install awscli
   aws login --profile zenite --region us-east-1   # abre el navegador; entrar como usuario IAM
   aws sts get-caller-identity --profile zenite      # confirma la cuenta 703461917799
   ```
   En AWS CloudShell no hace falta nada de esto: los scripts se suben y se corren ahí directamente.
3. **Crear y validar las instancias** `zp-ventas-01` (`10.20.0.10`), `zp-ventas-02` (`10.20.0.11`) y `zp-ti-01`
   (`10.20.0.102`): Amazon Linux 2023, `t3.micro`, sin IP pública ni llave SSH, administradas por EC2 Instance Connect
   Endpoint.
   ```bash
   cd Fase2/configuracion
   AWS_PROFILE=zenite bash 04_crear_instancias.sh            # crea (o reutiliza/enciende) y valida
   AWS_PROFILE=zenite bash 04_crear_instancias.sh --validar  # solo revisa
   ```
   Debe terminar en `RESULTADO: todo correcto.` Si AWS responde `PendingVerification` (cuenta nueva en verificación), esperar
   unos minutos y volver a correrlo: reutiliza lo que ya se creó.
4. **Conectarse a una instancia**: en la consola (región **N. Virginia**), *Instancia → Connect → EC2 Instance Connect →
   Connect using EC2 Instance Connect Endpoint* → `eice-zenite-fase2`, usuario `ec2-user`. O desde la terminal:
   ```bash
   AWS_PROFILE=zenite aws ec2-instance-connect ssh --instance-id <id> --os-user ec2-user --connection-type eice
   ```
5. **Pruebas de conectividad (MD_5)** dentro de las instancias:
   | Desde | Comando | Resultado esperado |
   |---|---|---|
   | `zp-ventas-01` | `ping -c 4 10.20.0.11` | Responde (E09) |
   | `zp-ventas-02` | `ping -c 4 10.20.0.10` | Responde (E10) |
   | `zp-ti-01` | `ping -c 4 10.20.0.10` | Responde (E11) |
   | `zp-ventas-01` | `ping -c 4 -W 2 10.20.0.102` | 100% de pérdida (E12) |
6. **Detener las instancias al terminar** (no cobran cómputo detenidas; `04_crear_instancias.sh` las vuelve a encender):
   ```bash
   AWS_PROFILE=zenite aws ec2 stop-instances --region us-east-1 \
     --instance-ids i-0f3bd7b0615933e00 i-05a7f9ee1a6e93000 i-0378a8624df39958b
   ```

Evidencias: `Fase2/evidencias/04_instancias/` (E07, E08, `info-fase2_<instancia>.txt`) y `Fase2/evidencias/05_pruebas/`
(E09 – E12). Resumen para el reporte (IDs, tipo, horas y costos): [Fase2/carlitos/](Fase2/carlitos/README.md).

No subir credenciales: el CSV de acceso a la consola (`*credentials*.csv`), `.env` y llaves están en `.gitignore`.
