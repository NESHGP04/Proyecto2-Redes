#!/usr/bin/env bash
# P1_costos.sh – Control de costos de la fase final (Persona 1). Solo lee: no crea, cambia ni borra nada.
# Ejecutar en AWS CloudShell. No guarda ni pide credenciales.
#
#   bash P1_costos.sh            qué cobra ahora en us-east-1 (instancias, NAT, Elastic IP, discos), estimación por hora y por día,
#                                y barrido de las demás regiones (no debería haber nada)
#   bash P1_costos.sh --gasto    gasto real del mes por servicio (Cost Explorer) y presupuestos con su alerta (AWS Budgets)
#   bash P1_costos.sh --todo     las dos cosas
#
# Los precios de la tabla son una estimación de us-east-1 (cambian: verifícalos en la calculadora de AWS). El gasto real
# manda: míralo en Billing. Cada consulta a Cost Explorer cuesta US$0.01. Salida en ~/final-config/costos.txt.
# Termina con error si hay recursos con cargo fuera de us-east-1 o Elastic IP sin asociar.
set -euo pipefail

REGION="us-east-1"
OUT_DIR="${OUT_DIR:-$HOME/final-config}"
MODO="${1:---resumen}"
case "$MODO" in --resumen|--gasto|--todo) ;; *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;; esac

# Estimación us-east-1 (US$): instancia por hora, NAT por hora, IPv4 pública por hora, EBS gp3 por GiB-mes
P_NAT="0.045"; P_IPV4="0.005"; P_GIB_MES="0.08"
precio_instancia() {
  case "$1" in t3.nano) echo 0.0052;; t3.micro) echo 0.0104;; t3.small) echo 0.0208;; t3.medium) echo 0.0416;; t3.large) echo 0.0832;; *) echo 0;; esac
}

mkdir -p "$OUT_DIR"
SALIDA="$OUT_DIR/costos.txt"
FALLAS=0
awsr() { aws --region "$1" --output json "${@:2}"; }
ok()    { printf '  [OK]    %-52s %s\n' "$1" "$2"; }
falla() { printf '  [FALLA] %-52s %s\n' "$1" "$2"; FALLAS=$((FALLAS+1)); }
info()  { printf '  [INFO]  %-52s %s\n' "$1" "$2"; }
aviso() { printf '  [ATENCION] %-49s %s\n' "$1" "$2"; }
mult() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.4f", a*b}'; }
suma() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.4f", a+b}'; }

resumen() {
  local INST NAT ADDR VOL n gib asoc libres total=0 nombre tipo c
  echo "  -- $REGION: lo que cobra ahora"
  INST=$(awsr "$REGION" ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,stopping,stopped")
  NAT=$(awsr "$REGION" ec2 describe-nat-gateways --filter "Name=state,Values=pending,available,deleting")
  ADDR=$(awsr "$REGION" ec2 describe-addresses)
  VOL=$(awsr "$REGION" ec2 describe-volumes)

  n=$(jq '[.Reservations[].Instances[] | select(.State.Name=="running" or .State.Name=="pending")] | length' <<<"$INST")
  if (( n == 0 )); then ok "Instancias encendidas" "0"
  else
    aviso "Instancias encendidas" "$n"
    while IFS=$'\t' read -r nombre tipo; do
      c=$(precio_instancia "$tipo"); total=$(suma "$total" "$c")
      printf '            %-22s %-10s ≈ US$%s/h\n' "$nombre" "$tipo" "$c"
    done < <(jq -r '.Reservations[].Instances[] | select(.State.Name=="running" or .State.Name=="pending")
                    | [(.Tags // [] | map(select(.Key=="Name").Value) | first // .InstanceId), .InstanceType] | @tsv' <<<"$INST")
  fi
  info "Instancias con IPv4 pública (Elastic IP incluidas)" "$(jq '[.Reservations[].Instances[] | select(.PublicIpAddress != null)] | length' <<<"$INST")"

  n=$(jq '.NatGateways | length' <<<"$NAT")
  if (( n == 0 )); then ok "NAT Gateways" "0"
  else aviso "NAT Gateways" "$n (≈ US\$$P_NAT/h cada uno, ≈ US\$1.08/día): destrúyelo al terminar la sesión"; total=$(suma "$total" "$(mult "$n" "$P_NAT")"); fi

  n=$(jq '.Addresses | length' <<<"$ADDR")
  asoc=$(jq '[.Addresses[] | select(.AssociationId != null)] | length' <<<"$ADDR")
  libres=$((n - asoc))
  info "Elastic IP" "$n en total · $asoc asociadas · $libres sin asociar (cada una ≈ US\$$P_IPV4/h aunque la instancia esté apagada)"
  total=$(suma "$total" "$(mult "$n" "$P_IPV4")")
  if (( libres > 0 )); then falla "Elastic IP sin asociar" "$libres: libérala o asóciala"; else ok "Elastic IP sin asociar" "0"; fi

  n=$(jq '.Volumes | length' <<<"$VOL"); gib=$(jq '[.Volumes[].Size] | add // 0' <<<"$VOL")
  info "Volúmenes EBS" "$n · $gib GiB (≈ US\$$(mult "$gib" "$P_GIB_MES")/mes, también con las instancias apagadas)"

  printf '  Estimación ahora: ≈ US$%s por hora · ≈ US$%s por día (cómputo + NAT + IPv4; sin discos ni tráfico)\n' \
    "$total" "$(mult "$total" 24)"
}

barrido() {
  local r ri rn ra rv extra=0
  echo "  -- Barrido de las demás regiones (instancias, NAT, Elastic IP, volúmenes)"
  while read -r r; do
    [[ -n "$r" && "$r" != "$REGION" ]] || continue
    ri=$(awsr "$r" ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" 2>/dev/null | jq '[.Reservations[].Instances[]] | length' 2>/dev/null || echo "?")
    rn=$(awsr "$r" ec2 describe-nat-gateways --filter "Name=state,Values=pending,available,deleting" 2>/dev/null | jq '.NatGateways | length' 2>/dev/null || echo "?")
    ra=$(awsr "$r" ec2 describe-addresses 2>/dev/null | jq '.Addresses | length' 2>/dev/null || echo "?")
    rv=$(awsr "$r" ec2 describe-volumes 2>/dev/null | jq '.Volumes | length' 2>/dev/null || echo "?")
    if [[ "$ri$rn$ra$rv" == "0000" ]]; then continue; fi
    extra=1
    if [[ "$ri$rn$ra$rv" == *"?"* ]]; then info "$r" "no se pudo consultar (región sin acceso)"
    else falla "Recursos en $r" "instancias=$ri nat=$rn elastic_ip=$ra volumenes=$rv"; fi
  done < <(awsr "$REGION" ec2 describe-regions | jq -r '.Regions[].RegionName' | sort)
  (( extra )) || ok "Otras regiones" "sin instancias, NAT, Elastic IP ni volúmenes"
}

gasto() {
  local INI FIN acc ce nombre b
  INI=$(date -u +%Y-%m-01)
  FIN=$(date -u -d tomorrow +%F 2>/dev/null || date -u -v+1d +%F)
  echo "  -- Gasto del mes ($INI a $FIN, Cost Explorer; puede tardar hasta un día en reflejar)"
  if ce=$(awsr us-east-1 ce get-cost-and-usage --time-period "Start=$INI,End=$FIN" --granularity MONTHLY \
          --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE 2>&1); then
    jq -r '[.ResultsByTime[].Groups[] | {s: .Keys[0], v: (.Metrics.UnblendedCost.Amount | tonumber)}]
           | group_by(.s) | map({s: .[0].s, v: (map(.v) | add)}) | sort_by(-.v)
           | (map(select(.v >= 0.005)) | .[] | "    \(.s)\t US$\(.v * 100 | round / 100)"),
             "  TOTAL DEL MES\t US$\(map(.v) | add // 0 | . * 100 | round / 100)"' <<<"$ce" | column -t -s$'\t' 2>/dev/null \
      || jq -r '.ResultsByTime[].Total' <<<"$ce"
  else
    info "Cost Explorer" "sin acceso o sin activar; mira Billing en la consola ($(echo "$ce" | head -1 | cut -c1-90))"
  fi
  echo "  -- Presupuestos y alertas (AWS Budgets)"
  acc=$(aws sts get-caller-identity --query Account --output text)
  if b=$(aws budgets describe-budgets --account-id "$acc" --output json 2>&1); then
    if [[ $(jq '.Budgets // [] | length' <<<"$b") == 0 ]]; then falla "Presupuestos" "ninguno creado"
    else
      while IFS= read -r nombre; do
        jq -r --arg n "$nombre" '.Budgets[] | select(.BudgetName==$n)
          | "  [INFO]  Presupuesto \(.BudgetName): límite \(.BudgetLimit.Amount) \(.BudgetLimit.Unit) · gastado \(.CalculatedSpend.ActualSpend.Amount // "?") · \(.TimeUnit)"' <<<"$b"
        aws budgets describe-notifications-for-budget --account-id "$acc" --budget-name "$nombre" --output json 2>/dev/null \
          | jq -r '.Notifications[]? | "            alerta: \(.NotificationType) \(.ComparisonOperator) \(.Threshold)\(if (.ThresholdType // "PERCENTAGE")=="PERCENTAGE" then "% del límite" else " (valor absoluto)" end)"' || true
      done < <(jq -r '.Budgets[].BudgetName' <<<"$b")
    fi
  else
    info "AWS Budgets" "sin acceso; revisa Billing > Budgets ($(echo "$b" | head -1 | cut -c1-90))"
  fi
}

{
  echo "Control de costos · cuenta $(aws sts get-caller-identity --query Account --output text) · $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
  case "$MODO" in
    --resumen) resumen; barrido ;;
    --gasto)   gasto ;;
    --todo)    resumen; barrido; gasto ;;
  esac
  if (( FALLAS == 0 )); then echo "RESULTADO: sin hallazgos."; else echo "RESULTADO: $FALLAS hallazgo(s); revísalos."; fi
  (( FALLAS == 0 ))   # el grupo va en un pipe: con pipefail su código de salida es el del script
} | tee "$SALIDA"
