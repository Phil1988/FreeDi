#!/bin/bash
# Runs as ExecStartPre of FreeDi.service, before FreeDiLCD starts.
#  1. wait until Moonraker accepts connections
#  2. make sure klippy-env has pyserial >= 3.5 (Klipper pins 3.4 and a Klipper
#     update reinstalls it, which breaks the LCD: read_until(expected=...), #536)
#  3. wait (with a timeout) until Klipper is ready, otherwise the LCD can miss the
#     ready event and stay on "connecting to Klipper" (#534). If Klipper does not
#     get ready (e.g. MCU needs flashing) FreeDi still starts after the timeout.

KLIPPER_READY_TIMEOUT=${KLIPPER_READY_TIMEOUT:-60}

SCRIPT_DIR="$( cd -- "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P )"  # /home/<user>/FreeDi/helpers
FREEDI_DIR="$( dirname "${SCRIPT_DIR}" )"                                            # /home/<user>/FreeDi
USER_HOME_DIR="$( dirname "${FREEDI_DIR}" )"                                         # /home/<user>
KLIPPER_ENV="${USER_HOME_DIR}/klippy-env"
FREEDI_CFG="${USER_HOME_DIR}/printer_data/config/freedi.cfg"

PORT=$(awk -F": " '/moonraker_port/ {print $2; exit}' "$FREEDI_CFG" 2>/dev/null | tr -d '\r\n ')
PORT=${PORT:-7125}

# 1. Moonraker
while ! (echo > "/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; do
    sleep 1
done

# 2. pyserial >= 3.5 in klippy-env (installed as the owner of the venv, not as root)
if [ -x "${KLIPPER_ENV}/bin/python" ] &&
    ! "${KLIPPER_ENV}/bin/python" -c 'import serial, sys; sys.exit(tuple(map(int, serial.__version__.split(".")[:2])) < (3, 5))' 2>/dev/null; then
    echo "pyserial < 3.5 in ${KLIPPER_ENV}, upgrading..."
    VENV_OWNER=$(stat -c %U "$KLIPPER_ENV")
    if [ "$(id -un)" = "$VENV_OWNER" ]; then
        "${KLIPPER_ENV}/bin/pip" install "pyserial>=3.5"
    else
        runuser -u "$VENV_OWNER" -- "${KLIPPER_ENV}/bin/pip" install "pyserial>=3.5"
    fi || echo "Warning: could not upgrade pyserial"
fi

# 3. Klipper ready (bounded)
for ((i = 0; i < KLIPPER_READY_TIMEOUT; i += 2)); do
    if curl -s --max-time 2 "http://127.0.0.1:${PORT}/printer/info" 2>/dev/null | grep -q '"state": *"ready"'; then
        echo "Klipper is ready."
        exit 0
    fi
    sleep 2
done
echo "Klipper not ready after ${KLIPPER_READY_TIMEOUT}s, starting FreeDi anyway."
exit 0
