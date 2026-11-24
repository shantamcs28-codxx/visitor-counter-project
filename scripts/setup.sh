#!/usr/bin/env bash
# Builds the image, creates two kind clusters (private + simulated public),
# installs metrics-server, deploys the app + HPA to both, starts the failover gateway.
set -euo pipefail
cd "$(dirname "$0")/.."

for t in docker kind kubectl; do
  command -v $t >/dev/null || { echo "Missing: $t  (brew install $t)"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "Start Docker Desktop first."; exit 1; }

echo "==> Building optimized image"
docker build -t visitor-counter:optimized .

for env in private public; do
  echo "==> Creating $env cluster"
  kind get clusters | grep -qx "$env" || kind create cluster --config hybrid/kind-$env.yaml
  kind load docker-image visitor-counter:optimized --name "$env"
  ctx="kind-$env"

  echo "==> metrics-server on $env"
  kubectl --context $ctx apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl --context $ctx -n kube-system patch deployment metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true

  echo "==> Deploying app to $env"
  kubectl --context $ctx apply -f k8s/redis.yaml
  sed "s/CLUSTER_NAME_PLACEHOLDER/${env}-cluster/" k8s/web.yaml | kubectl --context $ctx apply -f -
  kubectl --context $ctx apply -f k8s/hpa.yaml
  kubectl --context $ctx rollout status deployment/redis --timeout=120s
  kubectl --context $ctx rollout status deployment/web --timeout=120s
done

echo "==> Starting hybrid gateway on http://localhost:8080"
docker compose -f hybrid/docker-compose.gateway.yml up -d

echo
echo "Private : http://localhost:8081"
echo "Public  : http://localhost:8082"
echo "Gateway : http://localhost:8080  (private primary, public failover)"
