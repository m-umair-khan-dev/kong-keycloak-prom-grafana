# Fully Containerized (Docker-based) Kong & Monitoring Stack

This folder contains a fully containerized deployment of the **Kong API Gateway (Kong Manager)**, **Keycloak**, **Postgres**, and a containerized monitoring stack containing **Prometheus**, **Grafana**, and **Node Exporter**.

Unlike the hybrid systemd model, all services are managed entirely by Docker Compose.

---

## Folder Structure

* **`components/`**: Contains configuration and assets for all individual services in the stack:
  * **`grafana/`**: Contains Grafana datasource and dashboard provisioning rules, dashboard JSON files, and plugins configuration.
  * **`kong/`**: Clean, unmodified copy of the custom gateway codebase (containing rebranded UI assets and Dockerfile).
  * **`loki/`**: Contains Loki configuration for OTLP and log storage ([loki.yml](./components/loki/loki.yml)).
  * **`prometheus/`**: Stores containerized Prometheus configuration ([prometheus.yml](./components/prometheus/prometheus.yml)).
  * **`promtail/`**: Contains Promtail configuration to scrape Kong logs and attach metadata ([promtail.yml](./components/promtail/promtail.yml)).
  * **`tempo/`**: Contains Tempo configuration for distributed tracing.
* **`docker-compose.yml`**: Defines the unified service configuration for all containerized services.
* **`.env`**: Stores sensitive database passwords and administrative credentials.
* **`deploy.sh`**: Orchestration shell script to verify host paths, set folder ownership permissions, build/start containers, and initialize metrics collection.
* **`OBSERVABILITY.md`**: Detailed architecture guide mapping Prometheus metrics, Loki logs, and OpenTelemetry (Tempo) tracing ([OBSERVABILITY.md](./OBSERVABILITY.md)).

---

## Deployment Configuration & First-Time Setup

All deployment parameters, password configurations, and Keycloak admin credentials are isolated in the `.env` file at the root of this folder.

When you run the deployment script for the first time, if no `.env` file exists, it will automatically copy the [.env.example](./.env.example) template to `.env` and pause. **You must edit the newly created `.env` file to replace all `CHANGE_ME` placeholders with secure passwords before running the script again.**

### Configuration Variables
By default, `.env` contains:
* **`DATA_ROOT`**: Host directory mapped for Postgres, Prometheus, Loki, Tempo, and Grafana data storage (Default: `/home/xflow/data`).
* **`BYPASS_MOUNT_CHECK`**: Set to `true` to skip the check ensuring `DATA_ROOT` is a physically mounted disk partition. (Recommended `false` in production to prevent OS disk filling).

---

## How to Run & CLI Flags

The `deploy.sh` script provides robust CLI flags for managing the stack:

### 1. Start the Deployment
Simply run the script (it automatically uses `--up`):
```bash
chmod +x deploy.sh
./deploy.sh
```

### 2. Safe Teardown
To stop all containers gracefully:
```bash
./deploy.sh --down
```
*(The script will ask for interactive confirmation. Use `-y` to bypass.)*

### 3. Factory Reset / Clean Data
To forcefully stop all containers **and** delete all data stored in `DATA_ROOT`:
```bash
./deploy.sh --clean --force
```

### Additional Flags
* **`--skip-chown`**: Skips directory permission adjustments (useful on specific OS environments).
* **`--help` / `-h`**: Displays the full help menu.

---

## Access Endpoints

Once the installation is complete, the services will be accessible at:

* **Kong Proxy Port**: [http://localhost:8000](http://localhost:8000)
* **Kong Admin API**: [http://localhost:8001](http://localhost:8001)
* **Kong Manager (UI)**: [http://localhost:8002](http://localhost:8002)
* **Prometheus Dashboard**: [http://localhost:9090](http://localhost:9090)
* **Grafana Dashboard**: [http://localhost:3000](http://localhost:3000) (default credentials: `admin` / `admin`)
* **Loki Log Collector (API)**: [http://localhost:3100](http://localhost:3100)
* **Tempo Tracing (UI/API)**: [http://localhost:3200](http://localhost:3200)

---

## Scraping Metrics from Other VMs (Multi-Node Monitoring)

Since Prometheus runs inside a Docker container, it uses Docker's outbound routing to scrape external servers. You can easily expand the monitoring system to monitor other VMs.

### Step 1: Install Node Exporter on the target VM

Choose the method that fits your environment:

#### Method A: Using Package Manager (Easiest, internet required)
If the target VM has internet access, this is the simplest method as it automatically configures systemd services:
* **Ubuntu/Debian**:
  ```bash
  sudo apt update && sudo apt install -y prometheus-node-exporter
  ```
* **CentOS/RHEL/Rocky Linux**:
  ```bash
  sudo dnf install -y prometheus-node-exporter
  ```

#### Method B: Downloading directly from GitHub (Internet required)
To install the latest official release:
```bash
# Download latest package
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.0/node_exporter-1.8.0.linux-amd64.tar.gz

# Extract and install
tar -xzf node_exporter-1.8.0.linux-amd64.tar.gz
sudo cp node_exporter-1.8.0.linux-amd64/node_exporter /usr/local/bin/

# Set up systemd service
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
sudo bash -c "cat > /etc/systemd/system/node_exporter.service <<'EOS'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOS"

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

#### Method C: Offline Installation (No internet, air-gapped)
Copy the pre-downloaded package `monitoring/packages/node_exporter/node_exporter-1.10.2.linux-amd64.tar.gz` from the main stack directory to the target VM, then run:
```bash
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter
sudo tar -xzf node_exporter-1.10.2.linux-amd64.tar.gz -C /opt
sudo install -m 0755 /opt/node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/node_exporter

sudo bash -c "cat > /etc/systemd/system/node_exporter.service <<'EOS'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOS"

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
```

### Step 2: Open target ports
Make sure the target VM allows incoming traffic on port `9100` from the host VM IP where your Docker stack is running.

### Step 3: Add targets to Prometheus config
Edit [components/prometheus/prometheus.yml](./components/prometheus/prometheus.yml) on the host machine and append the external IP addresses to the `targets` block under the `node` job:
```yaml
  - job_name: node
    static_configs:
      - targets:
          - 'node-exporter:9100'  # Local containerized VM monitoring
          - '192.168.1.101:9100'  # External VM 1 IP address
          - '192.168.1.102:9100'  # External VM 2 IP address
```

### Step 4: Reload Prometheus without downtime
Instruct Prometheus to reload the configuration file from disk by sending a `SIGHUP` signal to the container:
```bash
docker compose exec prometheus kill -SIGHUP 1
```

---

## Keycloak Environment Settings & Production Considerations

When transitioning the stack from a development environment to staging or production, you should review and tweak the Keycloak configurations inside [docker-compose.yml](./docker-compose.yml):

### 1. Hostname Setup (Redirect URLs)
Keycloak generates OAuth redirect URLs based on host header request values. In production:
* Set **`KC_HOSTNAME`** to your public domain (e.g. `auth.xflowresearch.com`).
* Set **`KC_HOSTNAME_STRICT`** to `"true"` to enforce strict URL validation.

### 2. HTTPS and Proxy Settings
* **`KC_PROXY: edge`**: Configured by default. This trusts `X-Forwarded-For` and `X-Forwarded-Proto` headers sent by your edge proxy (Kong). Ensure your edge proxy terminates TLS correctly.
* **`KC_HTTP_ENABLED`**: Currently `"true"`. Turn this to `"false"` in production if you want Keycloak to reject unencrypted HTTP requests entirely.

### 3. Production Running Mode
* **`command: start-dev`**: Currently set for easy local execution.
* **Production recommendation**: Change the container command to `command: start` to run Keycloak in production mode (which optimizes caches, checks database constraints, and enforces SSL).

### 4. Admin User Credentials
* Administrative credentials (`KEYCLOAK_ADMIN` and `KEYCLOAK_ADMIN_PASSWORD`) are stored in [.env](./.env) at the root of this folder. Always configure unique credentials for each deployment environment.

---

## Rebranded Gateway GUI Branches

This repository maintains separate branches for customized/rebranded versions of the Kong Manager GUI:

* **[rebranded-kong-gui-ngc](../../tree/rebranded-kong-gui-ngc)**: Rebranded theme for Next G Cloud (NGC) using a purple and indigo color scheme, customized registration links, and NGC brand assets.
* **[rebranded-kong-gui-xflow](../../tree/rebranded-kong-gui-xflow)**: Rebranded theme for xFlow Research using the brand's signature royal blue and cyan color palette, support links, and xFlow logos.

To deploy a rebranded stack, checkout the respective branch and run the `./deploy.sh` script.
