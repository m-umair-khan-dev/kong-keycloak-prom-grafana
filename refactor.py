import re

with open("deploy.sh", "r") as f:
    content = f.read()

# Replace log functions
content = re.sub(r'\blog \b', 'log_info ', content)
content = re.sub(r'\bwarn \b', 'log_warn ', content)
content = re.sub(r'\berr \b', 'log_error ', content)

# Remove old log definitions
old_logs = """log() { printf '[INFO] %s\\n' "$*"; }
warn() { printf '[WARN] %s\\n' "$*"; }
err() { printf '[ERROR] %s\\n' "$*"; }
die() { err "$*"; exit 1; }"""

new_logs = """RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

log_info() { printf "${BLUE}[INFO]${NC} %s\\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\\n" "$*"; }
die() { log_error "$*"; exit 1; }"""

content = content.replace(old_logs, new_logs)

# Add .env loading and CLI parsing before DATA_ROOT check
cli_parsing = """# -----------------------------------------------------------------------------
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

# Enforce mandatory DATA_ROOT variable"""

content = content.replace("# Enforce mandatory DATA_ROOT variable", cli_parsing)

# Wrap chown commands with skip check
chown_start = "# Set correct ownership for containerized environments"
chown_logic = """  # Set correct ownership for containerized environments
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
  fi"""

content = re.sub(r'  # Set correct ownership for containerized environments.*?(?=\n})', chown_logic, content, flags=re.DOTALL)

with open("deploy.sh", "w") as f:
    f.write(content)

