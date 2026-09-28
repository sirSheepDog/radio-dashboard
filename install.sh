#!/bin/bash

set -e

INSTALL_DIR="/opt/radio-dashboard"
SERVICE_NAME="radio-dashboard"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo
echo "======================================"
echo "     Radio Station Dashboard"
echo "           Installation"
echo "======================================"
echo

if [ "$EUID" -ne 0 ]; then
    echo "Please run this installer with sudo:"
    echo
    echo "  sudo ./install.sh"
    echo
    exit 1
fi

# --------------------------------------------------
# Configuration
# --------------------------------------------------

DEFAULT_USER="${SUDO_USER:-$(logname 2>/dev/null || echo pi)}"

read -r -p "Linux username [${DEFAULT_USER}]: " DASHBOARD_USER
DASHBOARD_USER="${DASHBOARD_USER:-$DEFAULT_USER}"

read -r -p "Server host [0.0.0.0]: " SERVER_HOST
SERVER_HOST="${SERVER_HOST:-0.0.0.0}"

read -r -p "Server port [5000]: " SERVER_PORT
SERVER_PORT="${SERVER_PORT:-5000}"

echo
echo "Installation settings:"
echo "  User:       ${DASHBOARD_USER}"
echo "  Host:       ${SERVER_HOST}"
echo "  Port:       ${SERVER_PORT}"
echo "  Directory:  ${INSTALL_DIR}"
echo

read -r -p "Continue? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# --------------------------------------------------
# Validate user
# --------------------------------------------------

if ! id "$DASHBOARD_USER" >/dev/null 2>&1; then
    echo
    echo "ERROR: Linux user '${DASHBOARD_USER}' does not exist."
    exit 1
fi

# --------------------------------------------------
# Install system packages
# --------------------------------------------------

echo
echo "Installing required system packages..."

apt update
apt install -y \
    python3 \
    python3-venv \
    python3-pip

# --------------------------------------------------
# Stop existing service
# --------------------------------------------------

if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    echo
    echo "Stopping existing dashboard service..."
    systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true
fi

# --------------------------------------------------
# Create installation directory
# --------------------------------------------------

echo
echo "Creating installation directory..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/config"

# --------------------------------------------------
# Copy application files
# --------------------------------------------------

echo "Copying dashboard files..."

cp app.py "$INSTALL_DIR/"
cp requirements.txt "$INSTALL_DIR/"

cp -r templates "$INSTALL_DIR/"
cp -r static "$INSTALL_DIR/"

cp config/applications.yaml "$INSTALL_DIR/config/"

cp config/applications.yaml "$INSTALL_DIR/config/"
cp config/dashboard.yaml.example "$INSTALL_DIR/config/"
cp config/station.yaml.example "$INSTALL_DIR/config/"

# --------------------------------------------------
# Station configuration
# --------------------------------------------------

if [ -f "config/station.yaml" ]; then
    echo "Copying existing station configuration..."
    cp config/station.yaml "$INSTALL_DIR/config/"
elif [ -f "config/station.yaml.example" ]; then
    echo "Creating station configuration from example..."
    cp config/station.yaml.example "$INSTALL_DIR/config/station.yaml"
else
    echo "Creating default station configuration..."

    cat > "$INSTALL_DIR/config/station.yaml" <<EOF
callsign: YOURCALL
EOF
fi

# --------------------------------------------------
# Dashboard configuration
# --------------------------------------------------

echo "Creating dashboard configuration..."

cat > "$INSTALL_DIR/config/dashboard.yaml" <<EOF
user: ${DASHBOARD_USER}

server:
  host: ${SERVER_HOST}
  port: ${SERVER_PORT}
EOF

# --------------------------------------------------
# Python virtual environment
# --------------------------------------------------

echo
echo "Creating Python virtual environment..."

if [ ! -d "$INSTALL_DIR/.venv" ]; then
    python3 -m venv "$INSTALL_DIR/.venv"
fi

echo "Installing Python dependencies..."

"$INSTALL_DIR/.venv/bin/python" -m pip install --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

# --------------------------------------------------
# Set ownership
# --------------------------------------------------

echo
echo "Setting file ownership..."

chown -R "${DASHBOARD_USER}:${DASHBOARD_USER}" "$INSTALL_DIR"

# --------------------------------------------------
# Create systemd service
# --------------------------------------------------

echo "Creating systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Radio Station Dashboard
After=network.target graphical.target
Wants=network.target

[Service]
Type=simple
User=${DASHBOARD_USER}
Group=${DASHBOARD_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/.venv/bin/python ${INSTALL_DIR}/app.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# --------------------------------------------------
# Enable and start service
# --------------------------------------------------

echo
echo "Enabling dashboard service..."

systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service"

echo "Starting dashboard..."

systemctl start "$SERVICE_NAME.service"

# --------------------------------------------------
# Verify
# --------------------------------------------------

echo
echo "Waiting for dashboard to start..."
sleep 2

if systemctl is-active --quiet "$SERVICE_NAME.service"; then
    echo
    echo "======================================"
    echo "       Installation successful!"
    echo "======================================"
    echo
    echo "Dashboard:"
    echo "  http://${SERVER_HOST}:${SERVER_PORT}"
    echo
    echo "Service:"
    echo "  systemctl status ${SERVICE_NAME}"
    echo
    echo "Logs:"
    echo "  journalctl -u ${SERVICE_NAME} -f"
    echo
else
    echo
    echo "======================================"
    echo "       Installation failed"
    echo "======================================"
    echo
    echo "The service did not start successfully."
    echo
    echo "Check the logs with:"
    echo "  journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
    echo
    exit 1
fi
