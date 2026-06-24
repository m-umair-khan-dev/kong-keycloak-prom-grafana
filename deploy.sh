#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
err() { printf '[ERROR] %s\n' "$*"; }
die() { err "$*"; exit 1; }

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || die "sudo is required when not running as root"
  SUDO="sudo -n"
fi

run_root() {
  if [[ -n "${SUDO}" ]]; then
    ${SUDO} "$@"
  else
    "$@"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd docker
require_cmd curl
require_cmd mountpoint

# Enforce mandatory DATA_ROOT variable
if [[ -z "${DATA_ROOT:-}" ]]; then
  err "DATA_ROOT environment variable is not defined."
  err "Please specify where Postgres, Prometheus, and Grafana data should be stored."
  echo ""
  echo "Usage:"
  echo "  DATA_ROOT=/your/data/path ./deploy.sh"
  echo "  DATA_ROOT=/your/data/path BYPASS_MOUNT_CHECK=true ./deploy.sh"
  echo ""
  exit 1
fi
export DATA_ROOT

PROM_DATA_DIR="${DATA_ROOT}/prometheus"
GRAFANA_DATA_DIR="${DATA_ROOT}/grafana"
PG_DATA_DIR="${DATA_ROOT}/postgres"

ensure_data_root() {
  if [[ ! -d "${DATA_ROOT}" ]]; then
    err "DATA_ROOT directory does not exist: ${DATA_ROOT}"
    echo "Please create the directory first or specify a valid existing path."
    echo "Helping command to create it:"
    echo "  sudo mkdir -p ${DATA_ROOT}"
    die "Aborting installation."
  fi
  if [[ "${BYPASS_MOUNT_CHECK:-false}" != "true" ]]; then
    if ! mountpoint -q "${DATA_ROOT}"; then
      err "DATA_ROOT is not a mounted filesystem: ${DATA_ROOT}"
      echo "To bypass this check (e.g. for development or local VM), set BYPASS_MOUNT_CHECK=true."
      echo "Helping Command:"
      echo "  DATA_ROOT=${DATA_ROOT} BYPASS_MOUNT_CHECK=true ./deploy.sh"
      die "Aborting installation."
    fi
  fi

  # Create directories
  log "Creating host storage directories..."
  if [[ ! -d "${PROM_DATA_DIR}" || ! -d "${GRAFANA_DATA_DIR}" || ! -d "${PG_DATA_DIR}" ]]; then
    run_root mkdir -p "${PROM_DATA_DIR}" "${GRAFANA_DATA_DIR}" "${PG_DATA_DIR}" || true
  fi

  # Set correct ownership for containerized environments
  log "Adjusting directory permissions for Docker containers..."
  
  # Postgres (UID 70)
  run_root chown -R 70:70 "${PG_DATA_DIR}" || true
  
  # Prometheus (UID 65534 - nobody)
  run_root chown -R 65534:65534 "${PROM_DATA_DIR}" || true
  
  # Grafana (UID 472 - grafana)
  run_root chown -R 472:472 "${GRAFANA_DATA_DIR}" || true
}

start_docker_stack() {
  log "Building and starting containerized stack..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" build

  log "Starting database container..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d db

  log "Waiting for Postgres database to be ready..."
  local tries=30
  local wait_s=2
  local postgres_ready=false
  for i in $(seq 1 "${tries}"); do
    if docker exec postgres pg_isready -U nextgcloud -d postgres >/dev/null 2>&1; then
      log "Postgres is ready"
      postgres_ready=true
      break
    fi
    sleep "${wait_s}"
  done

  if [[ "${postgres_ready}" != "true" ]]; then
    die "Postgres did not become ready in time"
  fi

  log "Running Kong database migrations..."
  # If the database is already bootstrapped, we will fall back to kong migrations up
  if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm kong kong migrations bootstrap; then
    log "Bootstrap failed or already completed. Running kong migrations up..."
    docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm kong kong migrations up
  fi

  log "Starting all services..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d
}

wait_for_kong() {
  log "Waiting for Kong Admin API on http://localhost:8001/status"
  local tries=60
  local wait_s=2
  for i in $(seq 1 "${tries}"); do
    if curl -fsS http://localhost:8001/status >/dev/null 2>&1; then
      log "Kong Admin API is up"
      return 0
    fi
    sleep "${wait_s}"
  done
  die "Kong Admin API did not become ready"
}

enable_kong_prometheus() {
  log "Enabling Kong Prometheus plugin"
  local resp
  resp=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8001/plugins \
    --data "name=prometheus" \
    --data "config.status_code_metrics=true" \
    --data "config.latency_metrics=true" \
    --data "config.bandwidth_metrics=true")
  
  if [[ "${resp}" == "201" ]]; then
    log "Kong Prometheus plugin enabled"
  elif [[ "${resp}" == "409" ]]; then
    log "Kong Prometheus plugin already enabled. Updating configuration..."
    local plugin_id
    plugin_id=$(curl -s http://localhost:8001/plugins | grep -oE '"id":"[0-9a-f-]{36}"' | head -n 1 | cut -d'"' -f4)
    if [[ -n "${plugin_id}" ]]; then
      curl -s -o /dev/null -X PATCH "http://localhost:8001/plugins/${plugin_id}" \
        --data "config.status_code_metrics=true" \
        --data "config.latency_metrics=true" \
        --data "config.bandwidth_metrics=true"
      log "Kong Prometheus plugin configuration updated successfully"
    else
      warn "Could not determine Prometheus plugin ID to update configuration"
    fi
  else
    die "Failed to configure Kong Prometheus plugin (status ${resp})"
  fi
}

main() {
  ensure_data_root
  start_docker_stack
  wait_for_kong
  enable_kong_prometheus

  log "Deployment complete!"
  log "Kong Proxy:       http://localhost:8000"
  log "Kong Admin API:   http://localhost:8001"
  log "Kong Manager:     http://localhost:8002"
  log "Prometheus:       http://localhost:9090"
  log "Grafana:          http://localhost:3000"
}

main "$@"
