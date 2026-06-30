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


# -----------------------------------------------------------------------------
# Global Error Trapping
# -----------------------------------------------------------------------------
trap 'log_error "An unexpected error occurred on line $LINENO. Exiting."; exit 1' ERR
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
if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  if [[ -f "${ROOT_DIR}/.env.example" ]]; then
    log_info "No .env file found. Copying .env.example to .env..."
    cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
    log_warn "Please edit the newly created .env file to set your secure passwords, then run this script again."
    exit 1
  else
    die "No .env file found and no .env.example available."
  fi
fi

log_info "Loading environment variables from .env file..."
export $(grep -v '^#' "${ROOT_DIR}/.env" | xargs)

# Validate critical secrets
CRITICAL_SECRETS=("POSTGRES_PASSWORD" "KONG_PG_PASSWORD" "KC_DB_PASSWORD" "KEYCLOAK_ADMIN" "KEYCLOAK_ADMIN_PASSWORD" "GF_DATABASE_PASSWORD")
MISSING_SECRETS=0
for secret in "${CRITICAL_SECRETS[@]}"; do
  if [[ -z "${!secret:-}" || "${!secret}" == "CHANGE_ME" ]]; then
    log_error "Missing or unset critical secret in .env: ${secret}"
    MISSING_SECRETS=1
  fi
done

if [[ $MISSING_SECRETS -eq 1 ]]; then
  die "Please define all critical secrets in the .env file before proceeding."
fi

# Default Options
ACTION="up"
BYPASS_MOUNT_CHECK="${BYPASS_MOUNT_CHECK:-false}"
SKIP_CHOWN="false"
FORCE="false"
AUTO_YES="false"


# -----------------------------------------------------------------------------
# CLI Argument Parsing
# -----------------------------------------------------------------------------
show_help() {
  cat << 'HELP'
Usage: ./deploy.sh [OPTIONS]

Options:
  --up                      Start the deployment (default)
  --down                    Tear down the deployment safely
  --clean                   Tear down the deployment AND delete all data volumes
  --force                   Required when using --clean to confirm data deletion
  -y, --yes                 Skip interactive confirmation prompts
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
    --clean)
      ACTION="clean"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    -y|--yes)
      AUTO_YES="true"
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
  if [[ "${AUTO_YES}" != "true" ]]; then
    read -p "Are you sure you want to stop and remove all services? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Aborting teardown."
      exit 0
    fi
  fi
  log_info "Tearing down containerized stack..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" down
  log_success "Teardown complete."
  exit 0
fi

if [[ "${ACTION}" == "clean" ]]; then
  if [[ "${FORCE}" != "true" ]]; then
    die "The --clean flag requires the --force flag to prevent accidental data loss."
  fi
  
  if [[ "${AUTO_YES}" != "true" ]]; then
    log_warn "WARNING: This will DESTROY all containers AND all data in DATA_ROOT (${DATA_ROOT:-not set})."
    read -p "Are you absolutely sure you want to wipe everything? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      log_info "Aborting clean."
      exit 0
    fi
  fi
  
  log_info "Tearing down containerized stack and removing volumes..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" down -v
  if [[ -n "${DATA_ROOT:-}" && -d "${DATA_ROOT}" ]]; then
    log_info "Deleting host data directories in ${DATA_ROOT}..."
    run_root rm -rf "${DATA_ROOT:?}/"* || true
  fi
  log_success "Clean complete."
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

enable_kong_opentelemetry() {
  log_info "Enabling Kong OpenTelemetry plugin"
  # Full OTel config: Traces -> Tempo, Logs -> Loki (OTLP), enriched resource attributes
  local otel_config='{"name":"opentelemetry","config":{
    "traces_endpoint":"http://tempo:4318/v1/traces",
    "logs_endpoint":"http://loki:3100/otlp/v1/logs",
    "access_logs":{
      "endpoint":"http://loki:3100/otlp/v1/logs"
    },
    "metrics":{
      "endpoint":"http://prometheus:9090/api/v1/otlp/v1/metrics",
      "enable_latency_metrics":true,
      "enable_bandwidth_metrics":true,
      "enable_request_metrics":true,
      "enable_upstream_health_metrics":true
    },
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
        "access_logs":{
          "endpoint":"http://loki:3100/otlp/v1/logs"
        },
        "metrics":{
          "endpoint":"http://prometheus:9090/api/v1/otlp/v1/metrics",
          "enable_latency_metrics":true,
          "enable_bandwidth_metrics":true,
          "enable_request_metrics":true,
          "enable_upstream_health_metrics":true
        },
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
  # Enable unified OTLP telemetry (Traces, Logs, Metrics)
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
