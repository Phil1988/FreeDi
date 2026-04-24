#!/usr/bin/env bash
#
# FreeDi Installation Script
# Installs FreeDi modules, configures services, and sets up hardware dependencies
#
# Usage: ./install.sh [--image-build]
# Note: Do NOT run with sudo or as root - execute as a regular user
#

################################################################################
# COLOR DEFINITIONS
################################################################################
YLW='\033[1;33m'   # bold yellow
RED='\033[1;31m'   # bold red
GRN='\033[1;32m'   # bold green
RST='\033[0m'      # reset

################################################################################
# CONFIGURATION & VARIABLES
################################################################################

USER_NAME=$(id -un)
USER_GROUP=$(id -gn)
USER_HOME_DIR=$(eval echo "~$USER_NAME")
FREEDI_DIR="$( cd -- "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P )"

# Command-line options
IMAGE_BUILD=false
for arg in "$@"; do
    case "$arg" in
        --image-build)
            IMAGE_BUILD=true
            ;;
        *)
            printf "%b\n" "${RED}Error: Unknown argument '$arg'.${RST}"
            echo "Usage: ./install.sh [--image-build]"
            exit 1
            ;;
    esac
done

# Source configuration from separate config file
source "${FREEDI_DIR}/install/freedi_install.conf"

# Find OS Release codename
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_CODENAME="$VERSION_CODENAME"
else
    printf "%b\n" "${RED}Cannot determine OS codename. Exiting.${RST}"
    echo "Make sure you are running an Armbian-based distribution and that the /etc/os-release file exists."
    exit 1
fi

# ensure python3 exists and check exact supported versions
PY_VER=$(python3 -c 'import sys; printf = "%d.%d"; print(printf % (sys.version_info.major, sys.version_info.minor))' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$PY_VER" ]; then
    printf "%b\n" "${RED}Error: python3 is not installed or not working. FreeDi requires Python ${SUPPORTED_VERSIONS_JOINED}.${RST}"; exit 1
fi
printf "%b\n" "${GRN}Detected Python version: $PY_VER${RST}"
# Check if detected version is supported
HAS_PYTHON_313=false
SUPPORTED=false
for version in "${SUPPORTED_PYTHON_VERSIONS[@]}"; do
    if [ "$PY_VER" = "$version" ]; then
        SUPPORTED=true
        if [ "$version" = "3.13" ]; then
            HAS_PYTHON_313=true
        fi
        echo "Using supported Python $version"
        break
    fi
done

if [ "$SUPPORTED" = false ]; then
    printf "%b\n" "${RED}Error: Unsupported Python version $PY_VER. FreeDi only supports ${SUPPORTED_VERSIONS_JOINED}.${RST}"; exit 1
fi

# check for proc to determine if we are running on a Qidi X-6 Armbian image
DEVICE_MODEL="$(tr -d '\000' </proc/device-tree/model 2>/dev/null)"
if [[ "$DEVICE_MODEL" == *"Qidi X-6"* ]]; then
    IS_FREEDI_IMAGE=true
else
    IS_FREEDI_IMAGE=false
fi

# -------------------------------------------------------------------------
# Git index flags – quick reference
#
# --assume-unchanged <file>
#   • File no longer appears as “modified” → working tree stays clean.
#   • Git MAY overwrite the file when the upstream branch changes it.
#   • Good for:
#     local files that you have made temporary tweaks
#     **or**
#     files that do not exist in the remote repository (e.g. a new local symlink).
#
# --skip-worktree <file>
#   • File no longer appears as “modified” → working tree stays clean.
#   • Git will NOT touch the file on pull/merge; local version is kept.
#   • Good for:
#     permanently replacing a tracked file with your own copy/symlink and ensuring upstream updates never overwrite it.
#
# .git/info/exclude   (local ignore file)
#   • Works like .gitignore but is **never** pushed; applies only to this local repo.
#   • Suppresses UNTRACKED files from “git status” and “git add .”.
#   • Has NO effect on already tracked files (for those use the flags above).
#   • Project example: we create a new symlink
#       klippy/extras/freedi.py
#     which by the time did NOT exist in the upstream Klipper repo.  By adding the line
#       klippy/extras/freedi.py
#     to .git/info/exclude we keep the working tree clean while still allowing
#     the file to live only on the local printer.
# -------------------------------------------------------------------------

################################################################################
# GIT WHITELIST DEFINITIONS
################################################################################
# PULLABLE_FILES: Accept upstream updates (assume-unchanged)
# BLOCKED_FILES: Keep local version (skip-worktree)

# FreeDi repository files
PULLABLE_FILES_FREEDI=(
    "klippy/extras/freedi.py"
    "klippy/extras/auto_z_offset.py"
    "FreeDiLCD/freedi_update.sh"
)

BLOCKED_FILES_FREEDI=()

# Klipper repository files (not present in upstream)
PULLABLE_FILES_KLIPPER=(
    "klippy/extras/freedi.py"
    "klippy/extras/auto_z_offset.py"
)

BLOCKED_FILES_KLIPPER=()

# Abort if the script is executed with sudo/root
if [ "$EUID" -eq 0 ] || [ -n "$SUDO_USER" ]; then
    printf "%b\n" "${RED}Error: Do NOT run this script with sudo or as root. Execute it as a regular user.${RST}"; exit 1
fi

# Ask for mainboard type
dialog --stdout --title "Mainboard type" --backtitle "FreeDi installation" --yesno "Do you use the stock mainboard?" 7 60
dialog_exit=$?

if [ $dialog_exit -eq 0 ]; then
    # User selected "Yes"
    STOCK_MAINBOARD=true
    clear
    sleep 1
    echo "Starting the installation for stock mainboard..."
    PREREQ_DEB="${FREEDI_DIR}/helpers/freedi-prerequisites-1.0-all.deb"

    if [ ! -f "$PREREQ_DEB" ]; then
        printf "%b\n" "${RED}Error: Required package file not found at $PREREQ_DEB.${RST}"; exit 1
    fi

    PREREQ_PKG="$(dpkg-deb -f "$PREREQ_DEB" Package 2>/dev/null)"
    if [ -z "$PREREQ_PKG" ]; then
        printf "%b\n" "${RED}Error: Could not determine package name from $PREREQ_DEB.${RST}"; exit 1
    fi

    if dpkg-query -W -f='${Status}' "$PREREQ_PKG" 2>/dev/null | grep -q "install ok installed"; then
        echo "Package $PREREQ_PKG is already installed. Skipping installation."
    else
        sudo dpkg -i "$PREREQ_DEB"
        if [ $? -ne 0 ]; then
            printf "%b\n" "${RED}Error: Failed to install package $PREREQ_PKG.${RST}"; exit 1
        fi
    fi
elif [ $dialog_exit -eq 1 ]; then
    # User selected "No"
    STOCK_MAINBOARD=false
    # Show dialog with Continue/Abort options for non-stock mainboard warning
    dialog --title "NON-stock Mainboard Warning" \
           --backtitle "FreeDi installation" \
           --yes-label "Continue" \
           --no-label "Abort" \
           --yesno "Notice: You are using a NON-stock mainboard.\n\nThe script will try to complete the installation, but because of the large variety of hardware a flawless run cannot be guaranteed.\n\nIf problems occur, please open a ticket:\nhttps://github.com/Phil1988/FreeDi" 12 70
    if [ $? -ne 0 ]; then
        # User selected Abort
        clear
        printf "%b\n" "${RED}Installation cancelled by user.${RST}"; exit 1
    fi
else
    # User cancelled or closed the dialog (typically CTRL+C or ESC)
    printf "%b\n" "${RED}Installation cancelled by user.${RST}"; exit 1
fi


################################################################################
# PRE-FLIGHT CHECKS
################################################################################

# Klipper installation check
# Check for klipper, moonraker and mainsail directories to determine if Klipper is installed correctly
if [ ! -d "$KLIPPER_DIR" ] || [ ! -d "$MOONRAKER_DIR" ] || [ ! -d "$MAINSAIL_DIR" ] || [ ! -d "$CROWSNEST_DIR" ]; then
    dialog --stdout --title "Klipper installation missing" --backtitle "FreeDi installation" --yes-label "Yes" --no-label "No" --yesno "One or more required modules are missing (Klipper, Moonraker, Mainsail).\n\nShould Klipper installation via KIAUH be started?\n\nPlease install Klipper, Moonraker, Mainsail and Crowsnest." 10 70
    klipper_dialog_exit=$?

    if [ $klipper_dialog_exit -eq 0 ]; then
        clear
        echo "Starting Klipper installation via KIAUH..."
        # Clone KIAUH installer
        KIAUH_DIR="$USER_HOME_DIR/kiauh"
        if [ -d "$KIAUH_DIR" ]; then
            echo "KIAUH directory already exists at $KIAUH_DIR. Skipping clone."
        else
            git clone https://github.com/dw-0/kiauh.git "$KIAUH_DIR"
            if [ $? -ne 0 ]; then
                printf "%b\n" "${RED}Error: Failed to clone KIAUH repository.${RST}"; exit 1
            fi
        fi
    else
        clear
        printf "%b\n" "${RED}Error: Klipper directory not found at $KLIPPER_DIR. Please install Klipper first.${RST}"; exit 1
    fi
    clear
    # Run KIAUH installer
    bash "$KIAUH_DIR/kiauh.sh"
fi

# Create a symbolic links for needed modules to the Klipper extras directory
FREEDI_MODULES=(
    "freedi.py"
    "qidi_auto_z_offset/auto_z_offset.py"
    #"reverse_homing.py"
    #"hall_filament_width_sensor.py"
)

for MODULE_PATH in "${FREEDI_MODULES[@]}"; do
    MODULE_NAME=$(basename "${MODULE_PATH}")

    echo "Creating a symbolic link for ${MODULE_NAME} from ${REPO_MODULE_DIR}/${MODULE_PATH} to ${KLIPPER_EXTRAS_DIR} …"
    if ln -sf "${REPO_MODULE_DIR}/${MODULE_PATH}" "${KLIPPER_EXTRAS_DIR}/${MODULE_NAME}"; then
        # Ensure the symlink belongs to the regular user, not root
        chown -h "${USER_NAME}:${USER_GROUP}" "${KLIPPER_EXTRAS_DIR}/${MODULE_NAME}"
        echo "Successfully installed ${MODULE_NAME} to ${KLIPPER_EXTRAS_DIR}."
    else
        echo "Error: failed to create a symbolic link for ${MODULE_NAME}." >&2
        exit 1
    fi
done

################################################################################
# INSTALL APT PACKAGES (externalized to install/packages.sh)
################################################################################

echo "Installing apt packages from ${FREEDI_DIR}/install/packages.sh..."
if [ -f "${FREEDI_DIR}/install/packages.sh" ]; then
    # shellcheck source=/dev/null
    . "${FREEDI_DIR}/install/packages.sh"
else
    printf "%b\n" "${RED}Error: Package installation script not found at ${FREEDI_DIR}/install/packages.sh${RST}"; exit 1
fi

################################################################################
# GIT REPOSITORY VALIDATION & CONFIGURATION
################################################################################

# Check if the script is run inside a Git repository
if [ ! -d "${FREEDI_DIR}/.git" ]; then
    echo "Error: Not a git repository. Please initialize the repository first."
    exit 1
fi

# Ensure the Klipper extras directory exists
if [ ! -d "$KLIPPER_EXTRAS_DIR" ]; then
    echo "Error: Klipper extras directory not found at $KLIPPER_EXTRAS_DIR."
    echo "Make sure Klipper is installed correctly."
    exit 1
fi

# Wrapper to execute commands as the target user when running as root
# Especially useful for Git operations
run_as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$USER_NAME" -- "$@"
    else
        "$@"
    fi
}

# Helper: keep repo clean for a given list of files
# • pullable → assume-unchanged
# • blocked  → skip-worktree
# • detects & clears an already recorded change (typechange, content, …)
# • runs Git as $USER_NAME even when script is executed as root
clean_repo() {
    local repo="$1"
    local mode="$2"
    shift 2
    local files=("$@")

    # Determine the .git directory and build absolute path to info/exclude
    local git_dir
    git_dir="$(run_as_user git -C "$repo" rev-parse --git-dir)"
    local exclude_file="${repo}/${git_dir}/info/exclude"
    echo "Exclude file resolved to: $exclude_file"

    # Ensure the exclude file exists
    run_as_user mkdir -p "$(dirname "$exclude_file")"
    run_as_user touch "$exclude_file"

    for f in "${files[@]}"; do
        local full_path="${repo}/${f}"
        local st
        st="$(run_as_user git -C "$repo" status --porcelain -- "$f")"

        # Warn if file/symlink is missing in working tree
        if [ ! -e "$full_path" ]; then
            printf "%b\n" "${YLW}Notice: ${f} does not exist in working tree – index/ignore rules are still applied.${RST}"
        fi

        # ------------------------------------------------------------------
        # CASE 1 : tracked file or type-change
        # ------------------------------------------------------------------
        if run_as_user git -C "$repo" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
           || [[ $st =~ ^.?T ]]; then

            # Check if this file has changes already
            local dirty_pre=false
            if [ -n "$st" ]; then
                printf "%b\n" "${YLW}Detected changes for ${f} in index / working tree (causes dirty repo).${RST}"
                dirty_pre=true
            fi

            if [[ "$mode" == "pullable" ]]; then
                if run_as_user git -C "$repo" update-index --assume-unchanged -- "$f"; then
                    echo -e "Git will now ignore local changes to ${f} (assume-unchanged)."
                else
                    printf "%b\n" "${RED}Warning: git update-index failed for ${f} – file NOT marked.${RST}"
                fi
            else
                if run_as_user git -C "$repo" update-index --skip-worktree -- "$f"; then
                    echo -e "Git will keep your local version of ${f} (skip-worktree)."
                else
                    printf "%b\n" "${RED}Warning: git update-index failed for ${f} – file NOT marked.${RST}"
                fi
            fi

            # If it was dirty, refresh index to clear existing change
            if [ "$dirty_pre" = true ]; then
                printf "%b\n" "${YLW}Cleaning index / working tree for ${f}...${RST}"
                run_as_user git -C "$repo" update-index --really-refresh -q -- "$f"
                if run_as_user git -C "$repo" status --porcelain -- "$f" | grep -q .; then
                    printf "%b\n" "${RED}Index still reports changes for ${f}!${RST}"
                else
                    printf "%b\n" "${YLW}Index cleaned for ${f}.${RST}"
                fi
            fi

        # ------------------------------------------------------------------
        # CASE 2 : untracked file → add to info/exclude
        # ------------------------------------------------------------------
        else
            if ! grep -Fxq "$f" "$exclude_file"; then
                if printf '%s\n' "$f" | run_as_user tee -a "$exclude_file" >/dev/null; then
                    echo -e "Added ${f} to $(basename "$exclude_file") (untracked→exclude)."
                else
                    printf "%b\n" "${RED}Warning: failed to write ${f} to $(basename "$exclude_file").${RST}"
                fi
            else
                echo -e "${f} already listed in $(basename "$exclude_file") – skipping."
            fi
        fi
    done
}

# Apply git whitelist configuration
echo "Configuring git repositories for clean working tree..."
clean_repo "$FREEDI_DIR" pullable "${PULLABLE_FILES_FREEDI[@]}"
clean_repo "$FREEDI_DIR" blocked  "${BLOCKED_FILES_FREEDI[@]}"
clean_repo "$KLIPPER_DIR" pullable "${PULLABLE_FILES_KLIPPER[@]}"
clean_repo "$KLIPPER_DIR" blocked  "${BLOCKED_FILES_KLIPPER[@]}"

# Restart Klipper to load the new module
echo "Restarting Klipper service..."
sudo systemctl restart klipper

if [ $? -eq 0 ]; then
    echo "Klipper service restarted successfully."
    echo "Installation complete."
else
    printf "%b\n" "${RED}Error: Failed to restart Klipper service.${RST}"; exit 1
fi

################################################################################
# STOCK MAINBOARD CONFIGURATION
################################################################################
if [ "$STOCK_MAINBOARD" = true ]; then

    ### Setup serial port for LCD communication ####
    # Console output
    echo "Setup dtbo for serial communication..."
    # Install dtbo file for serial communication
    if [ ! -f "${DTBO_DIR}/rockchip-mkspi-uart1.dtbo" ]; then
        printf "%b\n" "${RED}Error: Source file ${DTBO_DIR}/rockchip-mkspi-uart1.dtbo does not exist. Aborting.${RST}"; exit 1
    fi
    sudo mkdir -p "$DTBO_TARGET"                                        # make sure directory exists
    sudo cp "${DTBO_DIR}/rockchip-mkspi-uart1.dtbo" "${DTBO_TARGET}/"
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to copy rockchip-mkspi-uart1.dtbo. Aborting.${RST}"; exit 1
    fi
    echo "dtbo install done!"

    # Stating the modification of the armbianEnv.txt
    echo "Customize the armbianEnv.txt file for serial communication..."
    # The file to check
    ARMBIAN_ENV_FILE="/boot/armbianEnv.txt"
    # The entry to search for
    SEARCH_STRING_OVERLAYS="overlays="
    # The new line to add or replace
    NEW_LINE_OVERLAYS="overlays=mkspi-uart1"

    # The entry to search for
    SEARCH_STRING_CONSOLE="console="
    # The new line to add or replace
    NEW_LINE_CONSOLE="console=none"


    # Check if the file exists
    if [ ! -f "$ARMBIAN_ENV_FILE" ]; then
        echo "File $ARMBIAN_ENV_FILE does not exist."
        exit 1
    fi

    # Check if the file contains the search string and perform the corresponding action
    if [ "$IS_FREEDI_IMAGE" = false ]; then
        if sudo grep -q "^$SEARCH_STRING_OVERLAYS" "$ARMBIAN_ENV_FILE"; then
            echo "Overlays line found. Replacing the line."
            sudo sed -i "s/^$SEARCH_STRING_OVERLAYS.*/$NEW_LINE_OVERLAYS/" "$ARMBIAN_ENV_FILE"
        else
            echo "Overlays line not found. Adding the line."
            echo "$NEW_LINE_OVERLAYS" | sudo tee -a "$ARMBIAN_ENV_FILE" > /dev/null
        fi
    fi

    # Check if the file contains the search string and perform the corresponding action
    if sudo grep -q "^$SEARCH_STRING_CONSOLE" "$ARMBIAN_ENV_FILE"; then
        echo "Console line found. Replacing the line."
        sudo sed -i "s/^$SEARCH_STRING_CONSOLE.*/$NEW_LINE_CONSOLE/" "$ARMBIAN_ENV_FILE"
    else
        echo "Console line not found. Adding the line."
        echo "$NEW_LINE_CONSOLE" | sudo tee -a "$ARMBIAN_ENV_FILE" > /dev/null
    fi


    echo "armbianEnv.txt file modified successfully!"


    ### Setup udev rules for ttyS2 ###

    echo "Creating udev rules for ttyS2..."
    echo 'KERNEL=="ttyS2",MODE="0660"' | sudo tee /etc/udev/rules.d/99-ttyS2.rules > /dev/null
    echo "udev rule for ttyS2 created."
    echo "Masking serial-getty service for ttyS2..."
    sudo systemctl mask serial-getty@ttyS2.service
    echo "serial-getty service for ttyS2 masked."
    echo "Reloading udev rules..."
    sudo udevadm control --reload-rules
    echo "udev rules reloaded."
    echo "Triggering udev events..."
    sudo udevadm trigger
    echo "udev events triggered."
fi   # end of stock mainboard section

################################################################################
# CONFIGURE TOOLHEAD SERIAL PORT
################################################################################

echo "Setup the toolhead serial path in printer.cfg..."

# Check if serial devices exist
if [ -d "/dev/serial/by-id" ]; then
    # Find the first available serial devices that contain "usb-Klipper_rp2040" in the name
    path=$(ls /dev/serial/by-id/* | grep "usb-Klipper_rp2040" | head -n 1)

    if [ -n "$path" ]; then
        echo "Found serial device: $path"

        # Check if the printer.cfg file exists
        if [ -f "$PRINTER_CONFIG" ]; then
            echo "Modifying printer.cfg"

            # Use sed to update the serial line only within the [mcu Toolhead] section
            sudo sed -i "/\[mcu Toolhead\]/,/^\[/ {s|^serial:.*|serial: ${path}|}" "$PRINTER_CONFIG"
            echo "Updated serial path for the toolhead in $PRINTER_CONFIG"
        else
            printf "%b\n" "${RED}Error: $PRINTER_CONFIG not found!${RST}"
        fi
    else
        echo "No serial device found in /dev/serial/by-id."
    fi
else
    printf "%b\n" "${RED}Error: no serial devices found in /dev/serial/by-id${RST}"
fi


################################################################################
# CONFIGURE PYTHON ENVIRONMENT
################################################################################

# Activate the Klipper virtual environment and install required Python packages
echo "Activating Klipper virtual environment and installing Python packages..."

if [ ! -d "$KLIPPER_ENV" ]; then
    printf "%b\n" "${RED}reKlippy env doesn't exist so I can't continue installation...${RST}"; exit 1
fi

PYTHON_V=$($KLIPPER_VENV_PYTHON_BIN -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
printf "%b\n" "${GRN}Klipper environment python version: $PYTHON_V${RST}"
# Arrange Python requirements from requirements.txt
echo "Arranging Python requirements..."
"${KLIPPER_ENV}/bin/pip" install --upgrade pip
"${KLIPPER_ENV}/bin/pip" install -r "${FREEDI_DIR}/requirements.txt"
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Failed to install Python requirements.${RST}"; exit 1
fi
echo "Python requirements installed from requirements.txt."

################################################################################
# CONFIGURE MOONRAKER
################################################################################

# Adding FreeDi section to moonraker update manager
echo "Adding FreeDi section to moonraker update manager..."

# Check if the file exists
if [ -f "${MOONRAKER_CONF}" ]; then
    echo "Moonraker configuration file ${MOONRAKER_CONF} found"

    # Check if the section [update_manager FreeDi] exists
    if grep -q "^\[update_manager FreeDi\]" "${MOONRAKER_CONF}"; then
        echo "The section [update_manager FreeDi] already exists in the file."
    else
        echo "The section [update_manager FreeDi] does not exist. Adding it to the end of the file."

        # Append the block to the end of the file
        cat <<EOL >> "${MOONRAKER_CONF}"
# FreeDi update_manager entry

[update_manager FreeDi]
type: git_repo
path: ~/FreeDi
channel: stable
origin: https://github.com/Phil1988/FreeDi
virtualenv: ~/klippy-env
requirements: requirements.txt
managed_services: FreeDi
info_tags:
    desc=FreeDi
    sparse_dirs:
    - FreeDiLCD
    - screen_firmwares

EOL
        echo "The section [update_manager FreeDi] has been added to the file."
    fi
else
    echo "File does not exist: ${MOONRAKER_CONF}"
    exit 1
fi

# Permit Moonraker to restart FreeDi service
echo "Permit Moonraker to restart FreeDi service..."

# Check if the file exists
if [ -f "${MOONRAKER_ASVC}" ]; then
    # Search for the string "FreeDi" in the file
    if grep -Fxq "FreeDi" "${MOONRAKER_ASVC}"; then
        echo "\"FreeDi\" is already present in the moonraker.asvc file. No changes made."
    else
        # Append "FreeDi" to the end of the file
        echo "FreeDi" >> "${MOONRAKER_ASVC}"
        echo "\"FreeDi\" has been added to the moonraker.asvc file."
    fi
else
    echo "moonraker.asvc file not found: ${MOONRAKER_ASVC}"
fi


################################################################################
# CONFIGURE NETWORK MANAGER
################################################################################

# Console output
echo "Changing permissions to enable nmcli commands without sudo (necessary for setting wifi via screen)..."

# Define variables
NETWORK_MANAGER_CONF_FILE="/etc/NetworkManager/NetworkManager.conf"

# Add the user to the netdev group
echo "Adding the user ${USER_NAME} to the 'netdev' group..."
sudo usermod -aG netdev "${USER_NAME}"

# Check if the auth-polkit line already exists in the config file
# Add the auth-polkit=false line after plugins=ifupdown,keyfile in the [main] section
if grep -q '^\[main\]' "$NETWORK_MANAGER_CONF_FILE"; then
    if ! grep -q '^auth-polkit=false' "$NETWORK_MANAGER_CONF_FILE"; then
        echo "Adding 'auth-polkit=false' to ${NETWORK_MANAGER_CONF_FILE}..."
        sudo sed -i '/^plugins=ifupdown,keyfile/a auth-polkit=false' "$NETWORK_MANAGER_CONF_FILE"
    else
        echo "'auth-polkit=false' is already present in ${NETWORK_MANAGER_CONF_FILE}."
    fi
else
    echo "The [main] section was not found in ${NETWORK_MANAGER_CONF_FILE}."
fi

# Display information
echo "User ${USER_NAME} has been successfully configured to run nmcli commands without sudo."


################################################################################
# CONFIGURE WIFI (externalized to install/wifi.sh)
################################################################################

echo "Running WiFi setup from ${FREEDI_DIR}/install/wifi.sh..."
if [ "$IS_FREEDI_IMAGE" != true ]; then
    if [ -f "${FREEDI_DIR}/install/wifi.sh" ]; then
        . "${FREEDI_DIR}/install/wifi.sh"
    else
        printf "%b\n" "${RED}Error: WiFi setup script not found at ${FREEDI_DIR}/install/wifi.sh${RST}"; exit 1
    fi
else
    echo "WiFi setup skipped, OS image already supports WiFi devices."
fi


################################################################################
# CONFIGURE USB MOUNTER SERVICE
################################################################################

# Creating udev rule
echo "Creating udev rule..."
#sudo echo 'ACTION=="add|remove", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ENV{DEVTYPE}=="partition", RUN+="/usr/bin/systemctl start usb-mount@%E{ACTION}-%k"' > /etc/udev/rules.d/99-usb-thumb.rules
echo 'ACTION=="add|remove", SUBSYSTEM=="block", KERNEL=="sd[a-z][0-9]*", ENV{DEVTYPE}=="partition", RUN+="/usr/bin/systemctl start usb-mount@%E{ACTION}-%k"' | sudo tee /etc/udev/rules.d/99-usb-thumb.rules > /dev/null

echo "Udev rule created: /etc/udev/rules.d/99-usb-thumb.rules"

# Creating systemd service file
echo "Creating systemd service file..."
sudo bash -c 'cat <<EOL > /etc/systemd/system/usb-mount@.service
[Unit]
Description=USB Mount Service (%i)

[Service]
Type=simple
ExecStart='"${FREEDI_DIR}"'/helpers/usbmounter.sh '"${USER_NAME}"' %i

EOL'
echo "Systemd service file created: /etc/systemd/system/usb-mount@.service"

# Make the script executable
echo "Making the usbmounter.sh executable..."
if [ ! -f "${FREEDI_DIR}/helpers/usbmounter.sh" ]; then
    printf "%b\n" "${RED}Error: File ${FREEDI_DIR}/helpers/usbmounter.sh does not exist. Aborting.${RST}"; exit 1
fi
chmod +x "${FREEDI_DIR}/helpers/usbmounter.sh"
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to set executable permission for usbmounter.sh. Aborting.${RST}"; exit 1
fi

# Reload udev and systemd
sudo udevadm control --reload-rules
sudo systemctl daemon-reload
echo "Udev and systemd have been reloaded."
echo "USB mounter service created successfully!"


################################################################################
# CONFIGURE FREEDI SERVICE
################################################################################

# Autostart the program
echo "Installing FreeDi service..."

# Stop running FreeDi service
echo "Stopping FreeDi service..."
sudo systemctl stop FreeDi.service
echo "FreeDi service stopped."

# Move FreeDi.service to systemd directory
echo "Moving FreeDi.service to /etc/systemd/system/"
if [ ! -f "${FREEDI_DIR}/helpers/FreeDi.service" ]; then
    printf "%b\n" "${RED}Error: Source file ${FREEDI_DIR}/helpers/FreeDi.service does not exist. Aborting.${RST}"; exit 1
fi
sudo cp "${FREEDI_DIR}/helpers/FreeDi.service" /etc/systemd/system/FreeDi.service
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to copy FreeDi.service to /etc/systemd/system/. Aborting.${RST}"; exit 1
fi
echo "FreeDi.service moved to /etc/systemd/system/"

# Setting current user in FreeDi.service
echo "Setting user to $USER_NAME in FreeDi.service"
if [ ! -f /etc/systemd/system/FreeDi.service ]; then
    printf "%b\n" "${RED}Error: File /etc/systemd/system/FreeDi.service does not exist. Aborting.${RST}"; exit 1
fi
sudo sed -i "s/{{USER}}/${USER_NAME}/g" /etc/systemd/system/FreeDi.service
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to replace user in /etc/systemd/system/FreeDi.service. Aborting.${RST}"; exit 1
fi

# Enable FreeDi.service to start at boot
echo "Enabling FreeDi.service to start at boot..."
sudo systemctl enable FreeDi.service
echo "FreeDi.service enabled to start at boot!"

################################################################################
# CONFIGURE AUTOFLASHER SERVICE
################################################################################

echo "Installing AutoFlasher.service..."
if [ ! -f "${FREEDI_DIR}/helpers/AutoFlasher.service" ]; then
    printf "%b\n" "${RED}Error: Source file ${FREEDI_DIR}/helpers/AutoFlasher.service does not exist. Aborting.${RST}"; exit 1
fi
sudo cp "${FREEDI_DIR}/helpers/AutoFlasher.service" /etc/systemd/system/AutoFlasher.service
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to copy AutoFlasher.service to /etc/systemd/system/. Aborting.${RST}"; exit 1
fi
echo "AutoFlasher.service installed!"

# Setting current user in AutoFlasher.service
echo "Setting user to $USER_NAME in AutoFlasher.service"

if [ ! -f "/etc/systemd/system/AutoFlasher.service" ]; then
    printf "%b\n" "${RED}Error: File /etc/systemd/system/AutoFlasher.service does not exist. Aborting.${RST}"; exit 1
fi
sudo sed -i "s/{{USER}}/${USER_NAME}/g" /etc/systemd/system/AutoFlasher.service
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to replace user in /etc/systemd/system/AutoFlasher.service. Aborting.${RST}"; exit 1
fi


# Make the script executable
if [ ! -f "${FREEDI_DIR}/helpers/klipper_auto_flasher.sh" ]; then
    printf "%b\n" "${RED}Error: File ${FREEDI_DIR}/helpers/klipper_auto_flasher.sh does not exist. Aborting.${RST}"; exit 1
fi
chmod +x "${FREEDI_DIR}/helpers/klipper_auto_flasher.sh"
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to set executable permission for klipper_auto_flasher.sh. Aborting.${RST}"; exit 1
fi

# Enable AutoFlasher.service to start at boot
echo "Enabling AutoFlasher.service to start at boot..."
sudo systemctl enable AutoFlasher.service
echo "AutoFlasher.service enabled to start at boot!"

# Make hid-flash executable
echo "Making hid-flash executable..."
if [ ! -f "${FREEDI_DIR}/helpers/hid-flash" ]; then
    printf "%b\n" "${RED}Error: File ${FREEDI_DIR}/helpers/hid-flash does not exist. Aborting.${RST}"; exit 1
fi
chmod +x "${FREEDI_DIR}/helpers/hid-flash"
if [ $? -ne 0 ]; then
    printf "%b\n" "${RED}Error: Failed to set executable permission for hid-flash. Aborting.${RST}"; exit 1
fi

echo "AutoFlasher.service installed!"
################################################################################
# FINALIZE INSTALLATION
################################################################################

# copy files from config_section/generic to printer_data/config overwriting existing files
if [ -d "${FREEDI_DIR}/config_section/generic" ]; then
    echo "Copying generic config section files to printer_data/config..."
    sudo cp -r "${FREEDI_DIR}/config_section/generic/." "$PRINTER_DATA_DIR/config/"
    sudo chown -R "${USER_NAME}:${USER_GROUP}" "$PRINTER_DATA_DIR/config/"
    echo "Generic config section files copied to printer_data/config."
else
    printf "%b\n" "${RED}Error: Source directory ${FREEDI_DIR}/config_section/generic does not exist. Aborting.${RST}"; exit 1
fi

# Check if crowsnest directory exists and ask if timelapse should be installed
if [ -d "$CROWSNEST_DIR" ] && [ ! -d "$TIMELAPSE_DIR" ]; then
    dialog --stdout --title "Crowsnest detected" --backtitle "FreeDi installation" --yes-label "Yes" --no-label "No" --yesno "Crowsnest directory detected at $CROWSNEST_DIR. Do you want to install the moonraker timelapse module?" 10 70
    if [ $? -eq 0 ]; then
        echo "Installing timelapse module from git..."
        # Clone the timelapse into home directory
        git clone https://github.com/mainsail-crew/moonraker-timelapse.git "$TIMELAPSE_DIR"
        if [ $? -ne 0 ]; then
            printf "%b\n" "${RED}Error: Failed to clone timelapse repository.${RST}"; exit 1
        fi
        echo "Timelapse module installed at $TIMELAPSE_DIR."
        # execute make install for timelapse module
        echo "Executing make install for timelapse module..."
        if [ -f "${TIMELAPSE_DIR}/Makefile" ]; then
            make -C "${TIMELAPSE_DIR}" install
            if [ $? -ne 0 ]; then
                printf "%b\n" "${RED}Error: Failed to execute make install for timelapse module.${RST}"; exit 1
            fi
            # add timlapse update to moonraker update manager
            echo "Adding timelapse update to moonraker update manager..."
            if [ -f "${MOONRAKER_CONF}" ]; then
                if grep -q "^\[update_manager timelapse\]" "${MOONRAKER_CONF}"; then
                    echo "The section [update_manager timelapse] already exists in the file."
                else
                    echo "The section [update_manager timelapse] does not exist. Adding it to the end of the file."

                    # Append the block to the end of the file
                    cat <<EOL >> "${MOONRAKER_CONF}"

# Timelapse module update_manager entry

[update_manager timelapse]
type: git_repo
primary_branch: main
path: ~/timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: klipper moonraker
EOL
                    echo "The section [update_manager timelapse] has been added to the file."
                fi
            else
                echo "File does not exist: ${MOONRAKER_CONF}"
                exit 1
            fi
            echo "Timelapse module installed successfully!"
        else
            printf "%b\n" "${RED}Error: Makefile not found in timelapse directory. Cannot install timelapse module.${RST}"; exit 1
        fi
    else
        echo "Timelapse module installation skipped."
    fi
elif [ -d "$TIMELAPSE_DIR" ]; then
    echo "Timelapse directory already exists at $TIMELAPSE_DIR. Skipping timelapse module installation."
fi

#remove kiauh directory if it was created during this installation
if [ -d "$KIAUH_DIR" ]; then
    echo "Removing KIAUH directory at $KIAUH_DIR..."
    rm -rf "$KIAUH_DIR"
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to remove KIAUH directory at $KIAUH_DIR. Please remove it manually.${RST}"; exit 1
    fi
fi

#remove kiauh_backups directory if it was created during this installation
KIAUH_BACKUP_DIR="$USER_HOME_DIR/kiauh_backups"
if [ -d "$KIAUH_BACKUP_DIR" ]; then
    echo "Removing KIAUH backup directory at $KIAUH_BACKUP_DIR..."
    rm -rf "$KIAUH_BACKUP_DIR"
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to remove KIAUH backup directory at $KIAUH_BACKUP_DIR. Please remove it manually.${RST}"; exit 1
    fi
fi

# touch printer_data/config/macros.cfg to prevent potential permission issues
if [ ! -f "$PRINTER_DATA_DIR/config/macros.cfg" ]; then
    sudo touch "$PRINTER_DATA_DIR/config/macros.cfg"
    sudo chown "${USER_NAME}:${USER_GROUP}" "$PRINTER_DATA_DIR/config/macros.cfg"
    echo "empty macros.cfg created at $PRINTER_DATA_DIR/config/macros.cfg."
fi

#remove moonraker.conf.backup if it was created during this installation
MOONRAKER_CONF_BACKUP="${MOONRAKER_CONF}.backup"
if [ -f "$MOONRAKER_CONF_BACKUP" ]; then
    echo "Removing Moonraker configuration backup file at $MOONRAKER_CONF_BACKUP..."
    rm -f "$MOONRAKER_CONF_BACKUP"
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to remove Moonraker configuration backup file at $MOONRAKER_CONF_BACKUP. Please remove it manually.${RST}"; exit 1
    fi
fi

# edit /etc/systemd/system/crowsnest service to restart on failure and delay starting by 5 seconds
if [ -f "/etc/systemd/system/crowsnest.service" ]; then
    echo "Configuring crowsnest.service to restart on failure and delay start by 5 seconds..."
    sudo sed -i '/\[Service\]/a Restart=on-failure\nRestartSec=5' /etc/systemd/system/crowsnest.service
    sudo sed -i '/\[Service\]/a ExecStartPre=/bin/sleep 5' /etc/systemd/system/crowsnest.service
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to configure crowsnest.service. Aborting.${RST}"; exit 1
    fi
    echo "crowsnest.service configured successfully."
    sudo systemctl restart crowsnest.service
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to restart crowsnest.service after configuration changes. Please check the service status and logs.${RST}"
    else
        echo "crowsnest.service restarted successfully with new configuration."
    fi
else
    echo "crowsnest.service not found at /etc/systemd/system/crowsnest.service. Skipping crowsnest service configuration."
fi

echo "Reloading systemd manager configuration..."
sudo systemctl daemon-reload
echo "systemd manager configuration reloaded."
echo "Starting FreeDi service..."
sudo systemctl start FreeDi.service
echo "FreeDi service started!"
if [ "$IMAGE_BUILD" = true ]; then
    echo "Image build mode enabled:"
    # clear machine-id to prevent conflicts when flashing the image to multiple devices
    echo "Clearing /etc/machine-id..."
    : | sudo tee /etc/machine-id >/dev/null
    if [ $? -ne 0 ]; then
        printf "%b\n" "${RED}Error: Failed to clear /etc/machine-id.${RST}"; exit 1
    fi
    # change sshd config to prevent root login via ssh and show last login info
    echo "Configuring sshd for image build..."
    SSHD_CONFIG="/etc/ssh/sshd_config"
    if [ -f "$SSHD_CONFIG" ]; then
        sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
        sudo sed -i 's/^#\?PrintLastLog.*/PrintLastLog yes/' "$SSHD_CONFIG"
        echo "sshd configuration updated for image build."
    else
        printf "%b\n" "${RED}Error: sshd_config file not found at $SSHD_CONFIG. Aborting.${RST}"; exit 1
    fi

    echo "Halting system for image build finalization..."
    sudo halt
else
    dialog --stdout --title "Reboot required" --backtitle "FreeDi installation" \
           --yes-label "Reboot now" --no-label "Reboot later" \
           --yesno "Installation complete!\n\nA reboot is required for all changes to take effect.\n\nReboot now?" 9 60
    if [ $? -eq 0 ]; then
        echo "Rebooting system..."
        sudo reboot
    else
        clear
        echo "=================================================================================="
        printf "%b\n" "${GRN}Setup complete!${RST}"
        printf "%b\n" "${YLW}Please reboot your system manually for the changes to take effect.${RST}"
        echo "=================================================================================="
    fi
fi
