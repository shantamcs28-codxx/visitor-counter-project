#!/usr/bin/env bash
# Task 2: self-healing demo on the private cluster.
set -euo pipefail
CTX=kind-private
echo "### Pods before"; kubectl --context $CTX get pods -o wide
POD=$(kubectl --context $CTX get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
echo; echo "### Deleting $POD"; kubectl --context $CTX delete pod "$POD" --wait=false
echo; echo "### Watching recovery (Ctrl+C after the new pod is Running 1/1)"
kubectl --context $CTX get pods -l app=web -w
