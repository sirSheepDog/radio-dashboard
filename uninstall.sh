#!/bin/bash

set -e

INSTALL_DIR="/opt/radio-dashboard"
SERVICE_NAME="radio-dashboard"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo
echo "======================================"
echo "     Radio Station Dashboard"
echo "           Uninstallation"
echo "======================================"
echo

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo:"
    echo
    echo "  sudo ./uninstall.sh"
    echo
    exit 1
fi

if [ ! -f "$SERVICE_FILE" ] && [ ! -d "$INSTALL_DIR" ]; then
    echo "Radio Station Dashboard does not appear to be installed."
    exit 0
fi

echo "This will remove:"
echo
echo "  Service:    ${SERVICE_NAME}.service"
echo "  Directory:  ${INSTALL_DIR}"
echo
echo "Your development copy in /home/pi/radio-dashboard will NOT be touched."
echo

read -r -p "Continue? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo
echo "Stopping dashboard service..."

systemctl disable --now "${SERVICE_NAME}.service" 2>/dev/null || true

echo "Removing systemd service..."

rm -f "$SERVICE_FILE"

systemctl daemon-reload
systemctl reset-failed "$SERVICE_NAME.service" 2>/dev/null || true

echo "Removing installed dashboard..."

rm -rf "$INSTALL_DIR"

echo
echo "======================================"
echo "       Uninstallation complete"
echo "======================================"
echo
echo "The installed dashboard and systemd service have been removed."
echo
echo "Your development copy remains at:"
echo "  /home/pi/radio-dashboard"
echo
