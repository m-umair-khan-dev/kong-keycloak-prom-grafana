#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
die() { log_error "$*"; exit 1; }

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

# -----------------------------------------------------------------------------
# Configuration and .env Loading
# -----------------------------------------------------------------------------
if [[ -f "${ROOT_DIR}/.env" ]]; then
  log_info "Loading environment variables from .env file..."
  export $(grep -v '^#' "${ROOT_DIR}/.env" | xargs)
fi

# Default Options
ACTION="up"
BYPASS_MOUNT_CHECK="${BYPASS_MOUNT_CHECK:-false}"
SKIP_CHOWN="false"

# -----------------------------------------------------------------------------
# CLI Argument Parsing
# -----------------------------------------------------------------------------
show_help() {
  cat << 'HELP'
Usage: ./deploy.sh [OPTIONS]

Options:
  --up                      Start the deployment (default)
  --down                    Tear down the deployment (docker compose down)
  --skip-chown              Skip chown permission adjustments
  --bypass-mount-check      Bypass the check ensuring DATA_ROOT is a mounted filesystem
  -h, --help                Show this help message

Environment Variables:
  DATA_ROOT                 Path to the storage root (loaded from .env if present)
HELP
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --up)
      ACTION="up"
      shift
      ;;
    --down)
      ACTION="down"
      shift
      ;;
    --skip-chown)
      SKIP_CHOWN="true"
      shift
      ;;
    --bypass-mount-check)
      BYPASS_MOUNT_CHECK="true"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

if [[ "${ACTION}" == "down" ]]; then
  log_info "Tearing down containerized stack..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" down
  log_success "Teardown complete."
  exit 0
fi

# Enforce mandatory DATA_ROOT variable
if [[ -z "${DATA_ROOT:-}" ]]; then
  log_error "DATA_ROOT environment variable is not defined."
  log_error "Please specify where Postgres, Prometheus, and Grafana data should be stored."
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
TEMPO_DATA_DIR="${DATA_ROOT}/tempo"
LOKI_DATA_DIR="${DATA_ROOT}/loki"

ensure_data_root() {
  if [[ ! -d "${DATA_ROOT}" ]]; then
  log_error "DATA_ROOT directory does not exist: ${DATA_ROOT}"
    echo "Please create the directory first or specify a valid existing path."
    echo "Helping command to create it:"
    echo "  sudo mkdir -p ${DATA_ROOT}"
    die "Aborting installation."
  fi
  if [[ "${BYPASS_MOUNT_CHECK:-false}" != "true" ]]; then
    if ! mountpoint -q "${DATA_ROOT}"; then
  log_error "DATA_ROOT is not a mounted filesystem: ${DATA_ROOT}"
      echo "To bypass this check (e.g. for development or local VM), set BYPASS_MOUNT_CHECK=true."
      echo "Helping Command:"
      echo "  DATA_ROOT=${DATA_ROOT} BYPASS_MOUNT_CHECK=true ./deploy.sh"
      die "Aborting installation."
    fi
  fi

  # Create directories
  log_info "Creating host storage directories..."
  run_root mkdir -p "${PROM_DATA_DIR}" "${GRAFANA_DATA_DIR}" "${PG_DATA_DIR}" "${TEMPO_DATA_DIR}" "${LOKI_DATA_DIR}" || true

  # Set correct ownership for containerized environments
  if [[ "${SKIP_CHOWN}" == "true" ]]; then
    log_info "Skipping directory permission adjustments (--skip-chown)"
  else
    log_info "Adjusting directory permissions for Docker containers..."
    
    # Postgres (UID 70)
    run_root chown -R 70:70 "${PG_DATA_DIR}" || true
    
    # Prometheus (UID 65534 - nobody)
    run_root chown -R 65534:65534 "${PROM_DATA_DIR}" || true
    
    # Grafana (UID 472 - grafana)
    run_root chown -R 472:472 "${GRAFANA_DATA_DIR}" || true

    # Tempo (UID 10001 - tempo)
    run_root chown -R 10001:10001 "${TEMPO_DATA_DIR}" || true

    # Loki (UID 10001 - loki uses same uid as tempo)
    run_root chown -R 10001:10001 "${LOKI_DATA_DIR}" || true
  fi
}

start_docker_stack() {
  log_info "Building and starting containerized stack..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" build

  log_info "Starting database and PgBouncer containers..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d db pgbouncer

  log_info "Waiting for Postgres database to be ready..."
  local tries=30
  local wait_s=2
  local postgres_ready=false
  for i in $(seq 1 "${tries}"); do
    if docker exec postgres pg_isready -U postgres -d postgres >/dev/null 2>&1; then
  log_info "Postgres is ready"
      postgres_ready=true
      break
    fi
    sleep "${wait_s}"
  done

  if [[ "${postgres_ready}" != "true" ]]; then
    die "Postgres did not become ready in time"
  fi

  log_info "Waiting for PgBouncer connection pooler to be ready..."
  local pgbouncer_ready=false
  for i in $(seq 1 "${tries}"); do
    if docker exec postgres pg_isready -h pgbouncer -p 6432 -U kong >/dev/null 2>&1; then
  log_info "PgBouncer is ready"
      pgbouncer_ready=true
      break
    fi
    sleep "${wait_s}"
  done

  if [[ "${pgbouncer_ready}" != "true" ]]; then
    die "PgBouncer did not become ready in time"
  fi

  log_info "Running Kong database migrations..."
  # If the database is already bootstrapped, we will fall back to kong migrations up
  if ! docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm kong kong migrations bootstrap; then
  log_info "Bootstrap failed or already completed. Running kong migrations up..."
    docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm kong kong migrations up
  fi

  log_info "Starting all services..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d
}

wait_for_kong() {
  log_info "Waiting for Kong Admin API on http://localhost:8001/status"
  local tries=60
  local wait_s=2
  for i in $(seq 1 "${tries}"); do
    if curl -fsS http://localhost:8001/status >/dev/null 2>&1; then
  log_info "Kong Admin API is up"
      return 0
    fi
    sleep "${wait_s}"
  done
  die "Kong Admin API did not become ready"
}

enable_kong_prometheus() {
  log_info "Enabling Kong Prometheus plugin"
  local resp
  resp=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8001/plugins \
    --data "name=prometheus" \
    --data "config.status_code_metrics=true" \
    --data "config.latency_metrics=true" \
    --data "config.bandwidth_metrics=true")
  
  if [[ "${resp}" == "201" ]]; then
  log_info "Kong Prometheus plugin enabled"
  elif [[ "${resp}" == "409" ]]; then
  log_info "Kong Prometheus plugin already enabled. Updating configuration..."
    local plugin_id
    plugin_id=$(curl -s "http://localhost:8001/plugins?name=prometheus" | grep -oE '"id":"[0-9a-f-]{36}"' | head -n 1 | cut -d'"' -f4)
    if [[ -n "${plugin_id}" ]]; then
      curl -s -o /dev/null -X PATCH "http://localhost:8001/plugins/${plugin_id}" \
        --data "config.status_code_metrics=true" \
        --data "config.latency_metrics=true" \
        --data "config.bandwidth_metrics=true"
  log_info "Kong Prometheus plugin configuration updated successfully"
    else
  log_warn "Could not determine Prometheus plugin ID to update configuration"
    fi
  else
    die "Failed to configure Kong Prometheus plugin (status ${resp})"
  fi
}

enable_kong_opentelemetry() {
  log_info "Enabling Kong OpenTelemetry plugin"
  # Full OTel config: Traces -> Tempo, Logs -> Loki (OTLP), enriched resource attributes
  local otel_config='{"name":"opentelemetry","config":{
    "traces_endpoint":"http://tempo:4318/v1/traces",
    "logs_endpoint":"http://loki:3100/otlp/v1/logs",
    "http_response_header_for_traceid":"X-Trace-Id",
    "sampling_rate":1.0,
    "resource_attributes":{
      "service.name":"kong-gateway",
      "service.version":"3.9.1",
      "deployment.environment":"production",
      "telemetry.sdk.name":"kong"
    },
    "propagation":{
      "default_format":"w3c",
      "extract":["w3c","b3","jaeger"],
      "inject":["w3c"]
    },
    "queue":{
      "max_batch_size":200,
      "max_coalescing_delay":1,
      "max_entries":10000
    }
  }}'

  local resp
  resp=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:8001/plugins \
    -H "Content-Type: application/json" \
    -d "${otel_config}")
  
  if [[ "${resp}" == "201" ]]; then
  log_info "Kong OpenTelemetry plugin enabled (traces + logs)"
  elif [[ "${resp}" == "409" ]]; then
  log_info "Kong OpenTelemetry plugin already enabled. Updating configuration..."
    local plugin_id
    plugin_id=$(curl -s "http://localhost:8001/plugins?name=opentelemetry" | grep -oE '"id":"[0-9a-f-]{36}"' | head -n 1 | cut -d'"' -f4)
    if [[ -n "${plugin_id}" ]]; then
      local update_config='{"config":{
        "traces_endpoint":"http://tempo:4318/v1/traces",
        "logs_endpoint":"http://loki:3100/otlp/v1/logs",
        "http_response_header_for_traceid":"X-Trace-Id",
        "sampling_rate":1.0,
        "resource_attributes":{
          "service.name":"kong-gateway",
          "service.version":"3.9.1",
          "deployment.environment":"production",
          "telemetry.sdk.name":"kong"
        },
        "propagation":{
          "default_format":"w3c",
          "extract":["w3c","b3","jaeger"],
          "inject":["w3c"]
        }
      }}'
      curl -s -o /dev/null -X PATCH "http://localhost:8001/plugins/${plugin_id}" \
        -H "Content-Type: application/json" \
        -d "${update_config}"
  log_info "Kong OpenTelemetry plugin updated (traces + logs)"
    else
  log_warn "Could not determine OpenTelemetry plugin ID to update configuration"
    fi
  else
    die "Failed to configure Kong OpenTelemetry plugin (status ${resp})"
  fi
}

main() {
  ensure_data_root
  start_docker_stack
  wait_for_kong
  enable_kong_prometheus
  enable_kong_opentelemetry

  log_info "Deployment complete!"
  log_info "Kong Proxy:       http://localhost:8000"
  log_info "Kong Admin API:   http://localhost:8001"
  log_info "Kong Manager:     http://localhost:8002"
  log_info "Prometheus:       http://localhost:9090"
  log_info "Grafana:          http://localhost:3000"
  log_info "Tempo API:        http://localhost:3200"
  log_info "Loki API:         http://localhost:3100"
}

main "$@"
