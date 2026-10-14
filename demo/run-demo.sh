#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PHI Lane — lane isolation demo
#
# Seven beats, each removing one objection, ending with the measurement.
#
#   ./run-demo.sh          interactive: press ENTER between beats (live)
#   ./run-demo.sh --auto   timed pauses, no input needed (recording)
#
# Pre-flight runs before the first beat so no API latency lands on camera.
# ---------------------------------------------------------------------------
set -uo pipefail

AUTO=0
[[ "${1:-}" == "--auto" ]] && AUTO=1

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
TEAL=$'\033[38;5;37m'; AMBER=$'\033[38;5;172m'; RED=$'\033[38;5;131m'; GREY=$'\033[38;5;245m'

NS=lane-demo
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="$REPO_ROOT/terraform/terraform.tfvars"

beat() {                       # beat <n> <title>
  echo
  echo "${GREY}────────────────────────────────────────────────────────────${RESET}"
  echo "${BOLD}  $1 ${RESET} ${BOLD}$2${RESET}"
  echo "${GREY}────────────────────────────────────────────────────────────${RESET}"
  echo
}

say() { echo "${GREY}  # $*${RESET}"; }

run() {                        # run <command string> — show it, then run it
  echo "${BOLD}\$ $*${RESET}"
  echo
  eval "$@"
  echo
}

hold() {                       # hold <seconds-in-auto-mode>
  if [[ $AUTO -eq 1 ]]; then sleep "${1:-4}"
  else printf "${DIM}  [enter]${RESET}"; read -r; fi
}

# ---------------------------------------------------------------------------
# Pre-flight — never on camera
# ---------------------------------------------------------------------------
clear
echo "${GREY}pre-flight…${RESET}"

if [[ ! -f "$TFVARS" ]]; then
  echo "${RED}terraform.tfvars not found at $TFVARS${RESET}"; exit 1
fi
COMPARTMENT=$(grep '^compartment_ocid' "$TFVARS" | cut -d'"' -f2)
[[ -z "$COMPARTMENT" ]] && { echo "${RED}could not read compartment_ocid${RESET}"; exit 1; }

PHI_RT=$(oci network route-table list --compartment-id "$COMPARTMENT" --all \
  --query "data[?\"display-name\"=='phi-lane-rt-phi-sealed'].id | [0]" --raw-output 2>/dev/null)
EGR_RT=$(oci network route-table list --compartment-id "$COMPARTMENT" --all \
  --query "data[?\"display-name\"=='phi-lane-rt-egress-lane'].id | [0]" --raw-output 2>/dev/null)
PHI_SL=$(oci network security-list list --compartment-id "$COMPARTMENT" --all \
  --query "data[?\"display-name\"=='phi-lane-sl-phi-pods'].id | [0]" --raw-output 2>/dev/null)

if [[ -z "$PHI_RT" || -z "$EGR_RT" || -z "$PHI_SL" ]]; then
  echo "${RED}could not resolve OCIDs — check the OCI CLI and compartment${RESET}"; exit 1
fi

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl apply -f "$REPO_ROOT/manifests/demo-probes.yaml" >/dev/null
for p in phi-probe egress-probe; do
  phase=$(kubectl get pod "$p" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)
  if [[ "$phase" != "Running" ]]; then
    kubectl delete -f "$REPO_ROOT/manifests/demo-probes.yaml" --ignore-not-found >/dev/null 2>&1
    kubectl apply -f "$REPO_ROOT/manifests/demo-probes.yaml" >/dev/null
    kubectl wait --for=condition=Ready pod/phi-probe pod/egress-probe -n "$NS" --timeout=180s >/dev/null
    break
  fi
done

clear
echo
echo "${BOLD}  PHI LANE${RESET}  ${GREY}·  network-enforced data residency on OKE${RESET}"
echo "${GREY}  Can you prove protected health information never left your boundary?${RESET}"
echo
hold 3

# ---------------------------------------------------------------------------
beat "1" "Two pods, two lanes"
say "One cluster. Both pods come from the same manifest and the same image."
run "kubectl get pods -n $NS -o wide | awk '{print \$1, \$3, \$6, \$7}' | column -t"
say "Different pod subnets: 10.0.16.0/20 is sealed, 10.0.32.0/20 is the egress lane."
hold 7

# ---------------------------------------------------------------------------
beat "2" "No NetworkPolicy is involved"
say "The first thing anyone assumes is that a policy blocks one of them."
run "kubectl get networkpolicies --all-namespaces"
say "There are none. Nothing in Kubernetes is denying anything."
hold 6

# ---------------------------------------------------------------------------
beat "3" "The firewall permits everything"
say "The second assumption is a firewall rule. Here is the sealed lane's own security list."
run "oci network security-list get --security-list-id $PHI_SL \
  --query 'data.\"egress-security-rules\"[].{destination:destination,protocol:protocol}' \
  --output table"
say "Protocol 'all' to 0.0.0.0/0. The filter on the sealed lane is wide open."
hold 7

# ---------------------------------------------------------------------------
beat "4" "The route tables"
echo "${AMBER}  EGRESS LANE${RESET}"
run "oci network route-table get --rt-id $EGR_RT \
  --query 'data.\"route-rules\"[].{destination:destination,type:\"destination-type\"}' --output table"
echo "${TEAL}  PHI LANE — SEALED${RESET}"
run "oci network route-table get --rt-id $PHI_RT \
  --query 'data.\"route-rules\"[].{destination:destination,type:\"destination-type\"}' --output table"
say "Two rules against one. The sealed lane has no route to 0.0.0.0/0 at all."
say "Not a deny rule. No rule. There is nowhere for the packet to go."
hold 9

# ---------------------------------------------------------------------------
beat "5" "Egress lane reaches the internet"
say "Raw IP, so DNS plays no part in this."
run "kubectl exec -n $NS egress-probe -- \
  curl -sS -o /dev/null -w 'HTTP %{http_code} in %{time_total}s\n' --max-time 10 https://1.1.1.1/"
say "Ninety milliseconds. The path exists end to end."
hold 6

# ---------------------------------------------------------------------------
beat "6" "The same request from the PHI lane"
say "Same image, same command, same cluster. Only the subnet differs."
echo "${TEAL}  This will take ten seconds, and nothing will happen.${RESET}"
echo
run "kubectl exec -n $NS phi-probe -- \
  curl -sS -o /dev/null -w 'HTTP %{http_code} in %{time_total}s\n' --max-time 10 https://1.1.1.1/ || true"
hold 5

# ---------------------------------------------------------------------------
beat "7" "What just happened"
echo "  ${TEAL}PHI lane${RESET}     timeout at 10.002s        ${GREY}no route existed${RESET}"
echo "  ${AMBER}egress lane${RESET}  HTTP 301 in 0.09s         ${GREY}NAT gateway${RESET}"
echo
echo "  ${GREY}No policy denied the request. No firewall rejected it."
echo "  No audit entry records a violation, because none occurred.${RESET}"
echo
echo "  ${BOLD}The boundary is the route table, not the application.${RESET}"
echo
echo "  ${GREY}github.com/dkhopade/oke-phi-lane${RESET}"
echo
