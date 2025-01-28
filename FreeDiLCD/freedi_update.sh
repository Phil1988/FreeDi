#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' freedi_update.sh
# Set variables

echo "Starting the freedi update process..."

USER_NAME=$(whoami)
SERVICE="FreeDi.service"
BKDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
HOMEDIR=$(dirname "$(dirname "${BKDIR}")")
BKDIR=$(dirname "${BKDIR}") # remove the last part of the path
FREEDI_LCD_DIR="${BKDIR}/FreeDiLCD"
REPO_MODULE_DIR="${BKDIR}/klipper_module"
LCD_FIRMWARE_DIR="${BKDIR}/screen_firmwares"

# Mark freedi_update.sh as unchanged in Git index, preventing it from being tracked for future modifications
git -C ${BKDIR} update-index --assume-unchanged FreeDiLCD/freedi_update.sh

# Varialbles for the klipper module
KLIPPER_EXTRAS_DIR="$HOMEDIR/klipper/klippy/extras"
MODULE_NAME="freedi.py"

# Cleaning klipper repo for all v1.20 users
echo "Cleaning klipper repo for all v1.20 users..."

if [ "$EUID" -eq 0 ]; then
    echo "Running as sudo or root."
else
    echo "Not running as sudo or root."
fi

# Sparse checkout the new required folders
git sparse-checkout add helpers/
git sparse-checkout add mainboard_and_toolhead_firmwares/

# Exclude freedi.py from the Klipper repo as we introduce it and thus shouldn't be considered by the repo
if ! grep -q "klippy/extras/${MODULE_NAME}" "${HOMEDIR}/klipper/.git/info/exclude"; then
    echo "klippy/extras/${MODULE_NAME}" >> "${HOMEDIR}/klipper/.git/info/exclude"
fi
echo "Successfully installed $MODULE_NAME to $KLIPPER_EXTRAS_DIR."
