from flask import Flask, render_template, redirect, url_for, jsonify
import subprocess
import yaml
import psutil
import os
import socket
import signal
import time

app = Flask(__name__)

DASHBOARD_CONFIG_FILE = "config/dashboard.yaml"

def load_dashboard_config():
    try:
        with open(DASHBOARD_CONFIG_FILE, "r") as file:
            return yaml.safe_load(file) or {}
    except FileNotFoundError:
        return {}

CONFIG_FILE = "config/applications.yaml"
STATION_CONFIG_FILE = "config/station.yaml"

DISPLAY = ":0"

dashboard_config = load_dashboard_config()

DASHBOARD_USER = dashboard_config.get("user", "pi")
HOME_DIRECTORY = os.path.expanduser(f"~{DASHBOARD_USER}")
XAUTHORITY = os.path.join(HOME_DIRECTORY, ".Xauthority")

AIOC_VENDOR_ID = "1209"
AIOC_PRODUCT_ID = "7388"


def load_config():
    with open(CONFIG_FILE, "r") as file:
        return yaml.safe_load(file)

def load_station_config():
    try:
        with open(STATION_CONFIG_FILE, "r") as file:
            return yaml.safe_load(file) or {}
    except FileNotFoundError:
        return {}

# ----------------------------------------------------------------------
# Systemd services
# ----------------------------------------------------------------------

def get_service_status(service_name):
    result = subprocess.run(
        ["systemctl", "is-active", service_name],
        capture_output=True,
        text=True
    )

    status = result.stdout.strip()

    if status == "active":
        return "running"
    elif status == "failed":
        return "failed"
    else:
        return "stopped"


def control_service(service_name, action):
    return subprocess.run(
        ["sudo", "-n", "systemctl", action, service_name],
        capture_output=True,
        text=True
    )


# ----------------------------------------------------------------------
# Local GUI applications
# ----------------------------------------------------------------------

def get_local_status(application):
    process_path = application["launch"]["process"]

    for process in psutil.process_iter(["pid", "exe", "cmdline"]):
        try:
            executable = process.info["exe"]

            if executable == process_path:
                return "running"

            cmdline = process.info["cmdline"]

            if cmdline and cmdline[0] == process_path:
                return "running"

        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    return "stopped"


def start_local(application):
    command = application["launch"]["command"]

    environment = os.environ.copy()
    environment["DISPLAY"] = DISPLAY
    environment["XAUTHORITY"] = XAUTHORITY
    environment["HOME"] = HOME_DIRECTORY

    try:
        subprocess.Popen(
            command,
            env=environment,
            cwd="/home/pi",
            start_new_session=True
        )
        return True

    except Exception as error:
        print(f"Failed to start {application['name']}: {error}")
        return False


# ----------------------------------------------------------------------
# Hardware / system status
# ----------------------------------------------------------------------

def is_aioc_connected():
    usb_path = "/sys/bus/usb/devices"

    try:
        for device in os.listdir(usb_path):
            vendor_file = os.path.join(
                usb_path, device, "idVendor"
            )
            product_file = os.path.join(
                usb_path, device, "idProduct"
            )

            if not os.path.exists(vendor_file):
                continue

            with open(vendor_file, "r") as file:
                vendor = file.read().strip()

            if vendor != AIOC_VENDOR_ID:
                continue

            if not os.path.exists(product_file):
                continue

            with open(product_file, "r") as file:
                product = file.read().strip()

            if product == AIOC_PRODUCT_ID:
                return True

    except (OSError, PermissionError):
        pass

    return False


def get_network_status():
    stats = psutil.net_if_stats()
    addresses = psutil.net_if_addrs()

    for interface, stat in stats.items():

        if not stat.isup:
            continue

        if interface == "lo":
            continue

        for address in addresses.get(interface, []):

            if address.family == socket.AF_INET:
                if not address.address.startswith("127."):
                    return True

    return False


# ----------------------------------------------------------------------
# Application status
# ----------------------------------------------------------------------

def get_application_statuses():
    config = load_config()
    statuses = {}

    for application in config["applications"]:

        if application["type"] == "service":
            service_name = application["service"]["name"]
            status = get_service_status(service_name)

        elif application["type"] == "local":
            status = get_local_status(application)

        else:
            status = "stopped"

        statuses[application["id"]] = status

    return statuses


# ----------------------------------------------------------------------
# Dashboard
# ----------------------------------------------------------------------

@app.route("/")
def index():
    config = load_config()
    station = load_station_config()

    for application in config["applications"]:

        if application["type"] == "service":
            service_name = application["service"]["name"]
            application["status"] = get_service_status(service_name)

        elif application["type"] == "local":
            application["status"] = get_local_status(application)

        else:
            application["status"] = "stopped"

    return render_template(
        "index.html",
        applications=config["applications"],
	station=station,
        cpu=psutil.cpu_percent(),
        memory=psutil.virtual_memory().percent,
        aioc_connected=is_aioc_connected(),
        network_connected=get_network_status()
    )


@app.route("/status")
def status():
    return jsonify({
        "applications": get_application_statuses(),
        "aioc_connected": is_aioc_connected(),
        "network_connected": get_network_status(),
        "cpu": psutil.cpu_percent(),
        "memory": psutil.virtual_memory().percent
    })


@app.route("/<app_id>/<action>", methods=["POST"])
def application_action(app_id, action):

    allowed_actions = ["start", "stop", "restart"]

    if action not in allowed_actions:
        return "Invalid action", 400

    config = load_config()

    for application in config["applications"]:

        if application["id"] != app_id:
            continue

        if application["type"] == "service":

            service_name = application["service"]["name"]
            control_service(service_name, action)

        elif application["type"] == "local":

            if action == "start":
                start_local(application)

            # Local GUI applications are intentionally not stopped
            # or restarted by the dashboard.

        break

    return redirect(url_for("index"))


if __name__ == "__main__":
    dashboard_config = load_dashboard_config()

    server_config = dashboard_config.get("server", {})

    host = server_config.get("host", "127.0.0.1")
    port = server_config.get("port", 5000)

    app.run(
        host=host,
        port=port,
        debug=False
    )
