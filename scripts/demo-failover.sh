#!/usr/bin/env bash
# Task 4: stop the private cluster and show traffic moving to the public one.
set -euo pipefail
hit() { curl -s --max-time 4 http://localhost:8080/api/count || echo '{"error":"no response"}'; }

echo "### Normal operation (should say private-cluster)"
for _ in 1 2 3; do hit; echo; sleep 1; done

echo; echo "### Stopping private cluster"
docker stop private-control-plane
sleep 3

echo; echo "### During outage (should say public-cluster)"
for _ in 1 2 3 4 5; do hit; echo; sleep 1; done

echo; echo "### Restoring private cluster"
docker start private-control-plane
echo "Give it ~60-90s, then: curl http://localhost:8080/api/count  (should return to private-cluster)"
