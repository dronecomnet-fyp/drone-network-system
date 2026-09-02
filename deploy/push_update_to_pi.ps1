# ==============================================================================
# Push Update to Raspberry Pi from Windows PowerShell (Offline Over SSH)
#
# Copies backend code and offline dependencies from Windows directly to the
# Raspberry Pi over SSH without requiring the Pi to have internet access.
#
# Usage:
#   .\deploy\push_update_to_pi.ps1 [PI_HOST] [PI_USER]
#
# Examples:
#   .\deploy\push_update_to_pi.ps1 10.42.0.1 drone
#   .\deploy\push_update_to_pi.ps1 drone-a.local drone
# ==============================================================================

param(
    [string]$TargetHost = "10.42.0.1",
    [string]$TargetUser = "drone"
)

$ErrorActionPreference = "Stop"

$RemoteDest = "/home/$TargetUser/rescue-mesh"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🚀 Updating Raspberry Pi at $TargetUser@$TargetHost" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Package backend files into a temporary tar archive to copy over scp fast
Write-Host "📦 [1/3] Packaging and copying backend code..." -ForegroundColor Yellow
$tempTar = "$env:TEMP\backend_update.tar.gz"
if (Test-Path $tempTar) { Remove-Item -Force $tempTar }

# Archive backend/ excluding .venv, __pycache__, etc.
tar -czf "$tempTar" --exclude=".venv" --exclude="__pycache__" --exclude=".pytest_cache" --exclude="data" backend

# Copy tar archive to Pi
scp "$tempTar" "$TargetUser@${TargetHost}:/tmp/backend_update.tar.gz"
Remove-Item -Force $tempTar

# Extract tar on Pi
ssh "$TargetUser@$TargetHost" "tar -xzf /tmp/backend_update.tar.gz -C $RemoteDest/ && rm /tmp/backend_update.tar.gz"

# 2. Copy offline Python wheels
Write-Host "📦 [2/3] Copying offline wheels..." -ForegroundColor Yellow
ssh "$TargetUser@$TargetHost" "mkdir -p /home/$TargetUser/wheels"
scp deploy/wheels/*.whl "$TargetUser@${TargetHost}:/home/$TargetUser/wheels/"

# 3. Install wheel and restart services on Pi
Write-Host "⚙️ [3/3] Installing offline package and restarting services..." -ForegroundColor Yellow

$remoteCommand = @"
set -e
VENV_PATH=`$HOME/rescue-mesh/backend/.venv
if [ -d "`$VENV_PATH" ]; then
    echo "Installing python-multipart wheel into virtualenv..."
    "`$VENV_PATH/bin/pip" install --no-index --find-links=`$HOME/wheels python-multipart
fi

echo "Restarting services..."
if systemctl list-unit-files | grep -q "rescue-portal.service"; then
    sudo systemctl restart rescue-portal rescue-mesh-api rescue-mesh-sync || true
else
    sudo systemctl restart drone-http.service drone-api.service || true
fi

echo "Checking node status..."
sleep 2
curl -s http://127.0.0.1/probe || echo "HTTP probe failed (check services)"
echo ""
echo "✅ Node update complete!"
"@

ssh -t "$TargetUser@$TargetHost" "$remoteCommand"

Write-Host ""
Write-Host "🎉 Successfully updated $TargetHost!" -ForegroundColor Green
