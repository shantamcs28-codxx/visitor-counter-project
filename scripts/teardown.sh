#!/usr/bin/env bash
cd "$(dirname "$0")/.."
docker compose -f hybrid/docker-compose.gateway.yml down 2>/dev/null
kind delete cluster --name private
kind delete cluster --name public
