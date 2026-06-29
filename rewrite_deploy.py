import re

with open("deploy.sh", "r") as f:
    content = f.read()

# 1. Add trap handler
trap_logic = """
# -----------------------------------------------------------------------------
# Global Error Trapping
# -----------------------------------------------------------------------------
trap 'log_error "An unexpected error occurred on line $LINENO. Exiting."; exit 1' ERR
"""
content = re.sub(r'(SUDO="")', trap_logic + r'\1', content, count=1)

# 2. Add interactive setup before .env loading
env_loading_old = """if [[ -f "${ROOT_DIR}/.env" ]]; then
  log_info "Loading environment variables from .env file..."
  export $(grep -v '^#' "${ROOT_DIR}/.env" | xargs)
fi"""

env_loading_new = """if [[ ! -f "${ROOT_DIR}/.env" ]]; then
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
fi"""

content = content.replace(env_loading_old, env_loading_new)

# 3. Update Default Options and CLI Parsing
options_old = """# Default Options
ACTION="up"
BYPASS_MOUNT_CHECK="${BYPASS_MOUNT_CHECK:-false}"
SKIP_CHOWN="false\""""

options_new = """# Default Options
ACTION="up"
BYPASS_MOUNT_CHECK="${BYPASS_MOUNT_CHECK:-false}"
SKIP_CHOWN="false"
FORCE="false"
AUTO_YES="false"
"""
content = content.replace(options_old, options_new)

help_old = """Options:
  --up                      Start the deployment (default)
  --down                    Tear down the deployment (docker compose down)
  --skip-chown              Skip chown permission adjustments
  --bypass-mount-check      Bypass the check ensuring DATA_ROOT is a mounted filesystem
  -h, --help                Show this help message"""

help_new = """Options:
  --up                      Start the deployment (default)
  --down                    Tear down the deployment safely
  --clean                   Tear down the deployment AND delete all data volumes
  --force                   Required when using --clean to confirm data deletion
  -y, --yes                 Skip interactive confirmation prompts
  --skip-chown              Skip chown permission adjustments
  --bypass-mount-check      Bypass the check ensuring DATA_ROOT is a mounted filesystem
  -h, --help                Show this help message"""

content = content.replace(help_old, help_new)

cli_cases_old = """    --down)
      ACTION="down"
      shift
      ;;"""

cli_cases_new = """    --down)
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
      ;;"""

content = content.replace(cli_cases_old, cli_cases_new)

# 4. Implement Tear Down Logic
down_logic_old = """if [[ "${ACTION}" == "down" ]]; then
  log_info "Tearing down containerized stack..."
  docker compose -f "${ROOT_DIR}/docker-compose.yml" down
  log_success "Teardown complete."
  exit 0
fi"""

down_logic_new = """if [[ "${ACTION}" == "down" ]]; then
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
fi"""

content = content.replace(down_logic_old, down_logic_new)

with open("deploy.sh", "w") as f:
    f.write(content)

