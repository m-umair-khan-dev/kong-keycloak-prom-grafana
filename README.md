# Fully Containerized (Docker-based) Kong & Monitoring Stack

This folder contains a fully containerized deployment of the **Kong API Gateway (xFlow Research Manager)**, **Keycloak**, **Postgres**, and a containerized monitoring stack containing **Prometheus**, **Grafana**, and **Node Exporter**.

Unlike the hybrid systemd model, all services are managed entirely by Docker Compose.

---

## Folder Structure

* **`kong/`**: Clean, unmodified copy of the custom gateway codebase (containing rebranded UI assets and Dockerfile).
* **`prometheus/`**: Stores containerized Prometheus configuration ([prometheus.yml](./prometheus/prometheus.yml)).
* **`grafana/`**: Contains Grafana datasource and dashboard provisioning rules, dashboard JSON files, and plugins configuration.
* **`loki/`**: Contains Loki configuration for OTLP and log storage ([loki.yml](./loki/loki.yml)).
* **`promtail/`**: Contains Promtail configuration to scrape Kong logs and attach metadata ([promtail.yml](./promtail/promtail.yml)).
* **`docker-compose.yml`**: Defines the unified service configuration for all containerized services.
* **`.env`**: Stores sensitive database passwords and administrative credentials.
* **`deploy.sh`**: Orchestration shell script to verify host paths, set folder ownership permissions, build/start containers, and initialize metrics collection.
* **`OBSERVABILITY.md`**: Detailed architecture guide mapping Prometheus metrics, Loki logs, and OpenTelemetry (Tempo) tracing ([OBSERVABILITY.md](./OBSERVABILITY.md)).

---

## Deployment Configuration

You can customize the script behavior via the following host environment variables:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `DATA_ROOT` | **None (Mandatory)** | Host directory mapped for Postgres, Prometheus, Loki, Tempo, and Grafana data storage. Must be an existing directory. |
| `BYPASS_MOUNT_CHECK` | `false` | Set to `true` to allow installation on directories that are not separate disk mountpoints (useful for local development/testing). |

All password configurations and Keycloak admin credentials are isolated in [.env](./.env) at the root of this folder.

### What is `BYPASS_MOUNT_CHECK=true`?
By default, the deployment script `deploy.sh` verifies that the `DATA_ROOT` directory is a **physically mounted disk partition** (such as a separate SSD, SAN, or external drive partition). 

* **Why this check exists**: In production, databases (Postgres) and metrics databases (Prometheus) perform high-frequency write operations. Storing this on your root partition (`/`) risks filling up the OS drive, which will lock up or crash the host system. Enforcing a separate mount point protects the OS.
* **What the bypass does**: Setting `BYPASS_MOUNT_CHECK=true` tells the script to skip this mount verification, allowing you to use any standard folder on your primary drive.
* **When to use it**: Set this to `true` during local development, sandbox testing, or on single-disk cloud VMs where a dedicated partition is not available.

---

## How to Run

### 1. Normal Production Deployment
Ensure your target storage drive is mounted (e.g., at `/mnt/xflow-data`), and run:
```bash
chmod +x deploy.sh
sudo DATA_ROOT=/mnt/xflow-data ./deploy.sh
```

### 2. Development / Sandbox Deployment (Bypassing Mount Check)
If you are deploying in a test VM or directory that is not an active partition mountpoint, run:
```bash
chmod +x deploy.sh
sudo DATA_ROOT=/your/data/path BYPASS_MOUNT_CHECK=true ./deploy.sh
```

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
Edit [prometheus/prometheus.yml](./prometheus/prometheus.yml) on the host machine and append the external IP addresses to the `targets` block under the `node` job:
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
