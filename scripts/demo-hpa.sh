#!/usr/bin/env bash
# Task 3: generate load and record replica count over time.
set -euo pipefail
cd "$(dirname "$0")/.."
CTX=kind-private
LOG=screenshots/hpa-log.txt
LOAD_PODS=${LOAD_PODS:-4}
: > "$LOG"

echo "Starting $LOAD_PODS load generators..."
for i in $(seq 1 $LOAD_PODS); do
  kubectl --context $CTX run load-$i --image=busybox:1.36 --restart=Never -- \
    /bin/sh -c 'while true; do wget -q -O- http://web/load >/dev/null; done' 2>/dev/null || true
done

record() {
  echo "$(date +%H:%M:%S) | $(kubectl --context $CTX get hpa web --no-headers | awk '{print "cpu/target="$3"  min="$4"  max="$5"  replicas="$6}')" | tee -a "$LOG"
}

echo "Recording every 15s for 6 minutes (load phase)..."
for _ in $(seq 1 24); do record; sleep 15; done

echo "Stopping load - watching scale-down for 5 minutes..."
for i in $(seq 1 $LOAD_PODS); do kubectl --context $CTX delete pod load-$i --ignore-not-found >/dev/null 2>&1; done
for _ in $(seq 1 20); do record; sleep 15; done
echo "Log saved to $LOG"
