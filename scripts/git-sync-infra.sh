#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# git-sync-infra.sh
# -----------------------------------------------------------------------------
# Helper script used by GitHub Actions to:
# 1. Enforce branch protection rules (GUI files on main, Infra files on branding).
# 2. Automatically propagate infrastructure updates from main to branding branches.
# -----------------------------------------------------------------------------

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION: GUI / Branding Files Definition
# -----------------------------------------------------------------------------
# List of paths or glob patterns containing GUI/Branding files.
# All paths are relative to the repository root.
GUI_PATTERNS=()

# Exception paths within GUI folders that are considered infrastructure.
GUI_EXCEPTIONS=()

# -----------------------------------------------------------------------------
# Helper: Classify file as GUI or Infrastructure
# -----------------------------------------------------------------------------
is_gui_file() {
  local file="$1"
  file="${file#./}" # Strip leading ./ if present
  
  # 1. Check exception list first (infra exception in GUI path)
  for exc in "${GUI_EXCEPTIONS[@]}"; do
    if [[ "$file" == "$exc" ]]; then
      return 1 # Not a GUI file (Infrastructure)
    fi
  done
  
  # 2. Check against GUI glob patterns
  for pattern in "${GUI_PATTERNS[@]}"; do
    if [[ "$file" == $pattern ]]; then
      return 0 # Matches GUI pattern
    fi
  done
  
  return 1 # Default: Infrastructure file
}

# -----------------------------------------------------------------------------
# Helper: Retrieve list of changed files in the push event
# -----------------------------------------------------------------------------
get_changed_files() {
  local before="$1"
  local after="$2"
  
  # Check if before SHA is empty or contains only zeros (new branch/commit push)
  if [[ -z "$before" || "$before" == "0000000000000000000000000000000000000000" ]]; then
    # Get files modified in the latest commit
    git diff-tree --no-commit-id --name-only -r HEAD
  else
    # Get files modified between before and after commits
    git diff --name-only "$before" "$after"
  fi
}

# -----------------------------------------------------------------------------
# MAIN SCRIPT EXECUTION
# -----------------------------------------------------------------------------
EVENT_BEFORE="${1:-}"
EVENT_AFTER="${2:-}"
REF_NAME="${3:-}"

echo "[INFO] Running Git Branching Strategy Check for branch: ${REF_NAME}"

# Detect and skip check for automated commits by github-actions
COMMIT_MSG=$(git log -1 --pretty=%B)
COMMIT_AUTHOR=$(git log -1 --pretty=%an)
if [[ "$COMMIT_MSG" == sync:* ]] || [[ "$COMMIT_AUTHOR" == *"github-actions"* ]]; then
  echo "[INFO] Automated commit detected ('${COMMIT_MSG}' by ${COMMIT_AUTHOR}). Skipping verification."
  exit 0
fi

# Fetch changed files
CHANGED_FILES=$(get_changed_files "${EVENT_BEFORE}" "${EVENT_AFTER}")

if [[ -z "${CHANGED_FILES}" ]]; then
  echo "[INFO] No file modifications detected in this push."
  exit 0
fi

echo "[INFO] List of modified files:"
echo "${CHANGED_FILES}"

# -----------------------------------------------------------------------------
# BRANCH STRATEGY CHECKS
# -----------------------------------------------------------------------------
if [[ "${REF_NAME}" == "main" ]]; then
  # Rule: main branch contains only shared infrastructure. No GUI files.
  offending_files=()
  for file in ${CHANGED_FILES}; do
    if is_gui_file "${file}"; then
      offending_files+=("${file}")
    fi
  done
  
  if [[ ${#offending_files[@]} -gt 0 ]]; then
    echo "::error::GUI/Branding files are not allowed to be committed to the main branch."
    echo "Offending GUI files:"
    for f in "${offending_files[@]}"; do
      echo "  - $f"
    done
    exit 1
  fi
  
  echo "[INFO] Validation succeeded: No GUI files found on main branch push."
  
  # Proceed to automatic synchronization
  echo "[INFO] Starting automatic synchronization to branding branches..."
  BRANDING_BRANCHES=("rebranded-kong-gui-xflow" "rebranded-kong-gui-ngc")
  
  # Filter out the GUI directories from propagating to branding branches
  INFRA_CHANGES=()
  for file in ${CHANGED_FILES}; do
    if [[ "$file" == components/kong/* ]]; then
      echo "[INFO] Skipping sync for Kong files (${file})"
      continue
    fi
    INFRA_CHANGES+=("$file")
  done
  
  # Configure git bot user
  git config user.name "Muhammad Umair Khan"
  git config user.email "umair.ims19@gmail.com"
  
  # Sync to each target branch
  for target_branch in "${BRANDING_BRANCHES[@]}"; do
    echo "[INFO] Syncing changed infra files to: ${target_branch}"
    
    # Fetch branch updates and checkout
    git fetch origin "${target_branch}"
    git checkout "${target_branch}"
    git pull origin "${target_branch}" --rebase || true
    
    # Selectively copy or delete only the changed infra files from main
    for f in "${INFRA_CHANGES[@]}"; do
      if git ls-tree -r main --name-only | grep -q "^${f}$"; then
        git checkout main -- "${f}"
      else
        # File was deleted in main, remove it here too
        git rm -q --ignore-unmatch "${f}" || true
        rm -f "${f}"
      fi
    done
    
    # Check if there are staging changes or working tree changes
    if git diff --quiet && git diff --cached --quiet; then
      echo "[INFO] No infrastructure differences for ${target_branch}. Skipping sync."
    else
      ORIGINAL_MSG=$(git log main -1 --pretty=%B)
      git add "${INFRA_CHANGES[@]}"
      git commit -m "sync: ${ORIGINAL_MSG}"
      git push origin "${target_branch}"
      echo "[INFO] Sync successful for ${target_branch}!"
    fi
    
    # Return back to main
    git checkout main
  done

else
  # Rule: Branding branches contain only GUI files. No direct infrastructure updates.
  offending_files=()
  for file in ${CHANGED_FILES}; do
    if ! is_gui_file "${file}"; then
      # Exception: GitHub actions config itself, or other config files we ignore?
      # Typically, no infrastructure modifications of any kind should be committed directly.
      offending_files+=("${file}")
    fi
  done
  
  if [[ ${#offending_files[@]} -gt 0 ]]; then
    echo "::error::Infrastructure changes are not allowed on branding branches. Please commit these changes to the main branch."
    echo "Offending infrastructure files:"
    for f in "${offending_files[@]}"; do
      echo "  - $f"
    done
    exit 1
  fi
  
  echo "[INFO] Validation succeeded: Only GUI files modified on branding branch push."
fi
