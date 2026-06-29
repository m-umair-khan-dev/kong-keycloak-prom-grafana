# Git Branching Strategy & Infrastructure Synchronization Workflow

This document explains the Git branching strategy and GitHub Actions automation configured for the repository.

---

## 1. Branch Layout

The repository uses a three-branch strategy:

*   **`main`**: The single source of truth for all **shared infrastructure and configuration** files. GUI/Branding files are strictly prohibited here.
*   **`rebranded-kong-gui-xflow`**: The branch containing the customized **xFlow Research** GUI branding assets, themes, and code. Direct infrastructure modifications are prohibited.
*   **`rebranded-kong-gui-ngc`**: The branch containing the customized **Next G Cloud** (NGC) GUI branding assets, themes, and code. Direct infrastructure modifications are prohibited.

---

## 2. File Classifications

All files in the repository are classified into two groups:

### A. GUI / Branding Files
These files are branch-specific and must never be synchronized from `main`. They include assets, layouts, styles, locales, and configuration specific to the rebranded manager UI:
*   Any files inside `kong/rebranded-kong/` **except** `Dockerfile` and `.dockerignore`.

### B. Infrastructure & Shared Configurations
These files are shared across all deployments and must remain identical across all branches. They are managed strictly on `main`:
*   `docker-compose.yml`
*   `deploy.sh`
*   `README.md` & `OBSERVABILITY.md`
*   `prometheus/**`, `grafana/**`, `loki/**`, `promtail/**`, `tempo/**`
*   `kong/rebranded-kong/Dockerfile` (and `.dockerignore`)
*   All other config scripts and database initializers.

---

## 3. Workflow Protections & Actions

The `.github/workflows/sync-infrastructure.yml` workflow enforces the layout integrity on every push:

### Rule 1: Protected `main` Branch
*   If a push to `main` contains any GUI/Branding files (as defined in the patterns list), the workflow **fails immediately** and prints the offending files.
*   This prevents developers from accidentally polluting the base branch with rebranded assets.

### Rule 2: Protected Branding Branches (`rebranded-kong-gui-xflow` & `rebranded-kong-gui-ngc`)
*   If a push directly to a branding branch contains any shared infrastructure file modifications, the workflow **fails immediately**.
*   It displays a message instructing the developer to commit those changes to the `main` branch instead.
*   *Note: Automated sync commits pushed by `github-actions[bot]` bypass this check.*

### Rule 3: Automatic Infrastructure Synchronization
*   When a valid commit containing only infrastructure changes is pushed to `main`, the workflow automatically checks out the target branding branches, extracts the specific infrastructure changes using `git checkout main -- <files>`, commits them under the message `sync: ...`, and pushes them back to both branches.
*   This ensures all branding branches are kept perfectly up-to-date with configuration, database, and monitoring stack improvements without manual pull requests.

---

## 4. Customizing File Patterns

The file classification rules are defined in `scripts/git-sync-infra.sh`. If you add new GUI directories or exception paths, edit these variables at the top of the script:

```bash
# List of paths or glob patterns containing GUI/Branding files
GUI_PATTERNS=(
  "kong/rebranded-kong/*"
)

# Exception paths within GUI folders that are considered infrastructure
GUI_EXCEPTIONS=(
  "kong/rebranded-kong/Dockerfile"
  "kong/rebranded-kong/.dockerignore"
)
```
