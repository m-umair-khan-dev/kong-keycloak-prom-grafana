#!/usr/bin/env bash
set -euo pipefail

NETWORK="kong-keycloak-prom-grafana_internal-net"
IMAGE="ghcr.io/marshallku/alpine-wrk"

echo "Pulling load test image..."
docker pull "${IMAGE}"

echo "Starting load test for Route 1 (/service1)..."
docker run --rm --network "${NETWORK}" "${IMAGE}" -t4 -c100 -d30s --latency https://kong:8443/service1

echo "Starting load test for Route 2 (/service2)..."
docker run --rm --network "${NETWORK}" "${IMAGE}" -t4 -c100 -d30s --latency https://kong:8443/service2

echo "Starting load test for Route 3 (/service3)..."
docker run --rm --network "${NETWORK}" "${IMAGE}" -t4 -c100 -d30s --latency https://kong:8443/service3

echo "Starting load test for Route 4 (/service4)..."
docker run --rm --network "${NETWORK}" "${IMAGE}" -t4 -c100 -d30s --latency https://kong:8443/service4

echo "Load tests completed!"
