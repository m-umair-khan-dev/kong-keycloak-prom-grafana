#!/usr/bin/env bash
set -euo pipefail

echo "Registering Service 1..."
curl -s -X POST http://localhost:8001/services -d name=service1 -d url=http://node-exporter:9100/ || true
curl -s -X POST http://localhost:8001/services/service1/routes -d name=route1 -d "paths[]=/service1" || true

echo "Registering Service 2..."
curl -s -X POST http://localhost:8001/services -d name=service2 -d url=http://node-exporter:9100/metrics || true
curl -s -X POST http://localhost:8001/services/service2/routes -d name=route2 -d "paths[]=/service2" || true

echo "Registering Service 3..."
curl -s -X POST http://localhost:8001/services -d name=service3 -d url=http://keycloak:8080/health || true
curl -s -X POST http://localhost:8001/services/service3/routes -d name=route3 -d "paths[]=/service3" || true

echo "Registering Service 4..."
curl -s -X POST http://localhost:8001/services -d name=service4 -d url=http://prometheus:9090/ || true
curl -s -X POST http://localhost:8001/services/service4/routes -d name=route4 -d "paths[]=/service4" || true

echo "Routes setup complete!"
