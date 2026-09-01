#!/usr/bin/env bash
# ==============================================================================
# Push Update to Raspberry Pi (Offline Over SSH)
#
# Copies backend code and offline dependencies from your laptop directly to the
# Raspberry Pi over SSH without requiring the Pi to have internet access.
#
# Usage:
#   ./deploy/push_update_to_pi.sh [PI_HOST] [PI_USER]
#
# Examples:
#   ./deploy/push_update_to_pi.sh 10.42.0.1 drone
#   ./deploy/push_update_to_pi.sh 192.168.1.50 pi
# ==============================================================================

set -euo pipefail

TARGET_HOST="${1:-10.42.0.1}"
TARGET_USER="${2:-drone}"
REMOTE_DEST="/home/${TARGET_USER}/rescue-mesh"

echo "============================================================"
echo "🚀 Updating Raspberry Pi at ${TARGET_USER}@${TARGET_HOST}"
echo "============================================================"

# 1. Sync backend code directly from laptop to Pi
echo "📦 [1/3] Syncing backend source code..."
rsync -avz --exclude '.venv' --exclude '__pycache__' --exclude '.pytest_cache' --exclude 'data' \
    ./backend/ "${TARGET_USER}@${TARGET_HOST}:${REMOTE_DEST}/backend/"

# 2. Sync offline wheels
echo "📦 [2/3] Syncing offline Python wheels..."
ssh "${TARGET_USER}@${TARGET_HOST}" "mkdir -p /home/${TARGET_USER}/wheels"
rsync -avz ./deploy/wheels/ "${TARGET_USER}@${TARGET_HOST}:/home/${TARGET_USER}/wheels/"

# 3. Install wheel and restart services on Pi
echo "⚙️ [3/3] Installing offline packages and restarting services..."
ssh -t "${TARGET_USER}@${TARGET_HOST}" bash << 'EOF'
  set -e
  VENV_PATH="$HOME/rescue-mesh/backend/.venv"
  if [ -d "$VENV_PATH" ]; then
    echo "Installing offline python-multipart wheel into virtualenv..."
    "$VENV_PATH/bin/pip" install --no-index --find-links="$HOME/wheels" python-multipart
  else
    echo "Virtualenv not found at $VENV_PATH, attempting global pip..."
    pip3 install --no-index --find-links="$HOME/wheels" python-multipart || true
  fi

  echo "Restarting services..."
  if systemctl list-unit-files | grep -q "rescue-portal.service"; then
    sudo systemctl restart rescue-portal rescue-mesh-api rescue-mesh-sync || true
  else
    sudo systemctl restart drone-http.service drone-api.service || true
  fi

  echo "Checking node health..."
  sleep 2
  curl -s http://127.0.0.1/health || echo "HTTP check failed (check services)"
  echo ""
  echo "✅ Node update complete!"
EOF

echo ""
echo "🎉 Update successfully pushed to ${TARGET_HOST}!"
