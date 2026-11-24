#!/usr/bin/env bash
# Task 5: measure BEFORE vs AFTER on the private cluster, then print the comparison table.
# Usage: ./scripts/cost-measure.sh before | after | report
set -euo pipefail
cd "$(dirname "$0")/.."
CTX=kind-private
mkdir -p results

# Assumed on-demand rates (edit to match your provider's price sheet)
CPU_PER_HR=0.0316      # USD per vCPU-hour
MEM_PER_HR=0.0042      # USD per GiB-hour
REG_PER_GB_MONTH=0.10  # USD per GB-month image storage
HOURS=730

sum_requests() {  # prints "<cpu_millicores> <mem_MiB>" for all pods
  kubectl --context $CTX get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.resources.requests.cpu}{" "}{.resources.requests.memory}{"\n"}{end}{end}' |
  awk '{c=$1; m=$2;
        if (c ~ /m$/) {sub(/m/,"",c)} else {c=c*1000}
        if (m ~ /Gi$/) {sub(/Gi/,"",m); m=m*1024} else if (m ~ /Mi$/) {sub(/Mi/,"",m)}
        C+=c; M+=m} END {print C+0, M+0}'
}
sum_usage() {
  kubectl --context $CTX top pods --no-headers 2>/dev/null |
  awk '{c=$2; m=$3; sub(/m/,"",c); sub(/Mi/,"",m); C+=c; M+=m} END {print C+0, M+0}'
}

case "${1:-}" in
  before)
    docker build -f Dockerfile.before -t visitor-counter:before .
    kind load docker-image visitor-counter:before --name private
    kubectl --context $CTX delete hpa web --ignore-not-found
    kubectl --context $CTX apply -f k8s/before/redis-before.yaml
    kubectl --context $CTX apply -f k8s/before/web-before.yaml
    kubectl --context $CTX rollout status deployment/web --timeout=180s
    kubectl --context $CTX rollout status deployment/redis --timeout=120s
    echo "Letting metrics settle (75s)..."; sleep 75
    IMG=$(docker image inspect visitor-counter:before --format '{{.Size}}')
    REPL=$(kubectl --context $CTX get deploy web -o jsonpath='{.status.readyReplicas}')
    read RC RM <<<"$(sum_requests)"; read UC UM <<<"$(sum_usage)"
    echo "IMG=$IMG REPL=$REPL RC=$RC RM=$RM UC=$UC UM=$UM" > results/before.env ;;
  after)
    docker build -t visitor-counter:optimized .
    kind load docker-image visitor-counter:optimized --name private
    kubectl --context $CTX apply -f k8s/redis.yaml
    sed "s/CLUSTER_NAME_PLACEHOLDER/private-cluster/" k8s/web.yaml | kubectl --context $CTX apply -f -
    kubectl --context $CTX apply -f k8s/hpa.yaml
    kubectl --context $CTX rollout restart deployment/web deployment/redis
    kubectl --context $CTX rollout status deployment/web --timeout=180s
    kubectl --context $CTX rollout status deployment/redis --timeout=120s
    echo "Letting metrics settle (75s)..."; sleep 75
    IMG=$(docker image inspect visitor-counter:optimized --format '{{.Size}}')
    REPL=$(kubectl --context $CTX get deploy web -o jsonpath='{.status.readyReplicas}')
    read RC RM <<<"$(sum_requests)"; read UC UM <<<"$(sum_usage)"
    echo "IMG=$IMG REPL=$REPL RC=$RC RM=$RM UC=$UC UM=$UM" > results/after.env ;;
  report)
    source results/before.env; B_IMG=$IMG B_REPL=$REPL B_RC=$RC B_RM=$RM B_UC=$UC B_UM=$UM
    source results/after.env;  A_IMG=$IMG A_REPL=$REPL A_RC=$RC A_RM=$RM A_UC=$UC A_UM=$UM
    awk -v bi=$B_IMG -v ai=$A_IMG -v br=$B_REPL -v ar=$A_REPL \
        -v brc=$B_RC -v arc=$A_RC -v brm=$B_RM -v arm=$A_RM \
        -v buc=$B_UC -v auc=$A_UC -v bum=$B_UM -v aum=$A_UM \
        -v cpu=$CPU_PER_HR -v mem=$MEM_PER_HR -v reg=$REG_PER_GB_MONTH -v h=$HOURS '
    function pct(b,a){ return b>0 ? sprintf("%.0f%%", (b-a)/b*100) : "-" }
    BEGIN {
      bcost = (brc/1000)*h*cpu + (brm/1024)*h*mem + (bi/1e9)*reg
      acost = (arc/1000)*h*cpu + (arm/1024)*h*mem + (ai/1e9)*reg
      print "| Metric | Before | After | Saving |"
      print "|---|---|---|---|"
      printf "| Image size | %.0f MB | %.0f MB | %s |\n", bi/1e6, ai/1e6, pct(bi,ai)
      printf "| Idle web replicas | %d | %d | %s |\n", br, ar, pct(br,ar)
      printf "| Total CPU requested (all pods) | %d m | %d m | %s |\n", brc, arc, pct(brc,arc)
      printf "| Total memory requested (all pods) | %d MiB | %d MiB | %s |\n", brm, arm, pct(brm,arm)
      printf "| Actual CPU used (idle, kubectl top) | %d m | %d m | - |\n", buc, auc
      printf "| Actual memory used (idle, kubectl top) | %d MiB | %d MiB | - |\n", bum, aum
      printf "| Est. monthly cost (reserved resources) | $%.2f | $%.2f | %s |\n", bcost, acost, pct(bcost,acost)
    }' | tee results/cost-table.md ;;
  *) echo "Usage: $0 before|after|report"; exit 1 ;;
esac
