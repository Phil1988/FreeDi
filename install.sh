#!/bin/bash
#
# FreeDi Installation Script
# Installs FreeDi modules, configures services, and sets up hardware dependencies
#
# Usage: ./install.sh
# Note: Do NOT run with sudo or as root - execute as a regular user
#

################################################################################
# CONFIGURATION & VARIABLES
################################################################################

FREEDI_DIR="$( cd -- "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P )"    # Absolute path to the FreeDi directory (/home/<user>/FreeDi)
FREEDI_LCD_DIR="${FREEDI_DIR}/FreeDiLCD"                                                # FreeDiLCD directory
REPO_MODULE_DIR="${FREEDI_DIR}/klipper_module"                                          # klipper_module directory
LCD_FIRMWARE_DIR="${FREEDI_DIR}/screen_firmwares"                                       # screen_firmwares directory
WIFI_DIR="${FREEDI_DIR}/helpers/wifi"                                                   # wifi driver directory
DTBO_DIR="${FREEDI_DIR}/helpers/dtbo"                                                   # dtbo directory

USER_HOME_DIR="$( dirname "${FREEDI_DIR}" )"                                            # One level up gives the user’s home directory -> /home/<user>
USER_NAME="$( basename "${USER_HOME_DIR}" )"                                            # The last path component is the user name -> <user>
USER_GROUP="$( id -gn "${USER_NAME}" )"                                                 # The group name of the user
SERVICE="FreeDi.service"                                                                # FreeDi systemd service

# External paths
KLIPPER_DIR="${USER_HOME_DIR}/klipper"                                                  # klipper directory
KLIPPER_EXTRAS_DIR="${KLIPPER_DIR}/klippy/extras"                                       # klipper module directory
PRINTER_DATA_DIR="${USER_HOME_DIR}/printer_data"                                        # printer data directory
PRINTER_CONFIG_DIR="${PRINTER_DATA_DIR}/config"                                         # printer config file
PRINTER_CONFIG="${PRINTER_CONFIG_DIR}/printer.cfg"                                      # printer config file
MOONRAKER_CONF="${PRINTER_CONFIG_DIR}/moonraker.conf"                                   # moonraker config file
MOONRAKER_ASVC="${PRINTER_DATA_DIR}/moonraker.asvc"                                     # Define moonraker.asvc file path

# Set python path to klipper env
KLIPPER_ENV="${USER_HOME_DIR}/klippy-env"                                               # klipper virtual environment
KLIPPER_VENV_PYTHON_BIN="$KLIPPER_ENV/bin/python"                                       # klipper python binary

DTBO_TARGET=/boot/dtb/rockchip/overlay                                                  # dtbo target directory for stock mainboard

# Find OS Release codename
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_CODENAME="$VERSION_CODENAME"
else
    echo "Cannot determine OS codename. Exiting."
    echo "Make sure you are running an Armbian-based distribution and that the /etc/os-release file exists."
    exit 1
fi

if python3 -c "import sys; exit(1) if sys.version_info < (3, 13) else exit(0)"; then
    echo "Python 3.13 or higher is installed."
    rm -f "${FREEDI_LCD_DIR}*311*.so"  # Remove incompatible Python 3.11 binaries if present
else
    echo "Python 3.13 or higher is NOT installed."
    rm -f "${FREEDI_LCD_DIR}*313*.so"  # Just in case, remove incompatible Python 3.13 binaries if present
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
    "klippy/extras/freedi_hall_filament_width_sensor.py"
)

BLOCKED_FILES_KLIPPER=()



# Abort if the script is executed with sudo/root
if [ "$EUID" -eq 0 ] || [ -n "$SUDO_USER" ]; then
    echo -e "${RED}Error: Do NOT run this script with sudo or as root. Execute it as a regular user.${RST}"
    exit 1
fi



# Ask for mainboard type
echo -e "${RED}Do you use the stock mainboard? (y/n)${RST}"
read -r RESPONSE

case "$RESPONSE" in
    y|Y)
        STOCK_MAINBOARD=true
        echo "Starting the installation for stock mainboard..."
        ;;

    n|N)
        STOCK_MAINBOARD=false
        echo -e "${YLW}Notice: You are using a NON-stock mainboard.${RST}"
        echo -e "${YLW}The script will try to complete the installation,${RST}"
        echo -e "${YLW}but because of the large variety of hardware${RST}"
        echo -e "${YLW}a flawless run cannot be guaranteed.${RST}"
        echo -e "${YLW}If problems occur, please open a ticket:${RST}"
        echo -e "${YLW}https://github.com/Phil1988/FreeDi${RST}"
        # red prompt — waits for a single key
        read -n1 -s -r -p $'\033[1;31mPress any key to acknowledge and continue...\033[0m'
        echo
        ;;

    *)
        echo -e "${RED}Error: Invalid answer. Please run the script again and choose 'y' or 'n'.${RST}"
        exit 1
        ;;
esac




################################################################################
# PRE-FLIGHT CHECKS
################################################################################

# Create a symbolic links for needed modules to the Klipper extras directory
FREEDI_MODULES=(
    "freedi.py"
    "qidi_auto_z_offset/auto_z_offset.py"
    #"reverse_homing.py"
    #"hall_filament_width_sensor.py"
    "freedi_hall_filament_width_sensor.py"
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




###### Sparse checkout required folders ######

# Sparse checkout only the required folders
# echo "Sparse checkout only the required folders..."
# git sparse-checkout add FreeDiLCD/
# git sparse-checkout add helpers/
# git sparse-checkout add klipper_module/
# git sparse-checkout add mainboard_and_toolhead_firmwares/
# git sparse-checkout add screen_firmwares/



###### Installing klipper modules ######

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
    # <-- changed: use absolute path for exclude file
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
            echo -e "${YLW}Notice: ${f} does not exist in working tree – index/ignore rules are still applied.${RST}"
        fi

        # ------------------------------------------------------------------
        # CASE 1 : tracked file or type-change
        # ------------------------------------------------------------------
        if run_as_user git -C "$repo" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
           || [[ $st =~ ^.?T ]]; then

            # Check if this file has changes already
            local dirty_pre=false
            if [ -n "$st" ]; then
                echo -e "${YLW}Detected changes for ${f} in index / working tree (causes dirty repo).${RST}"
                dirty_pre=true
            fi

            if [[ "$mode" == "pullable" ]]; then
                if run_as_user git -C "$repo" update-index --assume-unchanged -- "$f"; then
                    echo -e "Git will now ignore local changes to ${f} (assume-unchanged)."
                else
                    echo -e "${RED}Warning: git update-index failed for ${f} – file NOT marked.${RST}"
                fi
            else
                if run_as_user git -C "$repo" update-index --skip-worktree -- "$f"; then
                    echo -e "Git will keep your local version of ${f} (skip-worktree)."
                else
                    echo -e "${RED}Warning: git update-index failed for ${f} – file NOT marked.${RST}"
                fi
            fi

            # If it was dirty, refresh index to clear existing change
            if [ "$dirty_pre" = true ]; then
                echo -e "${YLW}Cleaning index / working tree for ${f}...${RST}"
                run_as_user git -C "$repo" update-index --really-refresh -q -- "$f"
                if run_as_user git -C "$repo" status --porcelain -- "$f" | grep -q .; then
                    echo -e "${RED}Index still reports changes for ${f}!${RST}"
                else
                    echo -e "${YLW}Index cleaned for ${f}.${RST}"
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
                    echo -e "${RED}Warning: failed to write ${f} to $(basename "$exclude_file").${RST}"
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
    echo "Error: Failed to restart Klipper service."
    exit 1
fi


################################################################################
# INSTALL SYSTEM DEPENDENCIES
################################################################################
# for flashing the toolhead katapult firmware using flashtool.py

echo "Checking if python3-serial package is already installed..."
if dpkg -l | grep -q python3-serial; then
    echo "python3-serial package is already installed. Skipping installation."
else
    echo "python3-serial package is not installed. Installing now..."
    sudo apt update && sudo apt install -y python3-serial
    
    if [ $? -eq 0 ]; then
        echo "python3-serial package installed successfully!"
    else
        echo "Failed to install python3-serial package."
        exit 1
    fi
fi


# Install stlink-tools (for Plus4 toolhead flashing)
# for flashing the Plus4 toolhead klipper firmware

echo "Checking if stlink-tools package is already installed..."
if dpkg -l | grep -q stlink-tools; then
    echo "stlink-tools package is already installed. Skipping installation."
else
    echo "stlink-tools package is not installed. Installing now..."
    sudo apt update && sudo apt install -y stlink-tools
    
    if [ $? -eq 0 ]; then
        echo "stlink-tools package installed successfully!"
    else
        echo "Failed to install stlink-tools package."
        exit 1
    fi
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
        echo "Error: Source file ${DTBO_DIR}/rockchip-mkspi-uart1.dtbo does not exist. Aborting."
        exit 1
    fi
    sudo mkdir -p "$DTBO_TARGET"                                        # make sure directory exists
    sudo cp "${DTBO_DIR}/rockchip-mkspi-uart1.dtbo" "${DTBO_TARGET}/"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy rockchip-mkspi-uart1.dtbo. Aborting."
        exit 1
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
    if sudo grep -q "^$SEARCH_STRING_OVERLAYS" "$ARMBIAN_ENV_FILE"; then
        echo "Overlays line found. Replacing the line."
        sudo sed -i "s/^$SEARCH_STRING_OVERLAYS.*/$NEW_LINE_OVERLAYS/" "$ARMBIAN_ENV_FILE"
    else
        echo "Overlays line not found. Adding the line."
        echo "$NEW_LINE_OVERLAYS" | sudo tee -a "$ARMBIAN_ENV_FILE" > /dev/null
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
            echo "Error: $PRINTER_CONFIG not found!"
        fi
    else
        echo "No serial device found in /dev/serial/by-id."
    fi
else
    echo "Error: no serial devices found in /dev/serial/by-id"
fi


################################################################################
# CONFIGURE PYTHON ENVIRONMENT
################################################################################

# Activate the Klipper virtual environment and install required Python packages
echo "Activating Klipper virtual environment and installing Python packages..."

if [ ! -d "$KLIPPER_ENV" ]; then
	echo "Klippy env doesn't exist so I can't continue installation..."
	exit 1
fi

PYTHON_V=$($KLIPPER_VENV_PYTHON_BIN -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "Klipper environment python version: $PYTHON_V"

# Arrange Python requirements from requirements.txt
echo "Arranging Python requirements..."
"${KLIPPER_ENV}/bin/pip" install --upgrade pip 
"${KLIPPER_ENV}/bin/pip" install -r "${FREEDI_DIR}/requirements.txt"
if [ $? -ne 0 ]; then
    echo "Failed to install Python requirements."
    exit 1
fi
echo "Python requirements installed from requirements.txt."

################################################################################
# INSTALL INPUT SHAPING DEPENDENCIES
################################################################################

echo "Installing required packages for input shaping..."

if $OS_CODENAME == "trixie"; then
    # For Debian 13 (trixie) and later, libatlas3-base is available instead of libatlas-base-dev
    sudo apt install -y libatlas3-base libopenblas-dev ntfs-3g
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install system dependencies."
        exit 1
    fi
else
    # For older versions, use libatlas-base-dev
    sudo apt install -y libatlas-base-dev libopenblas-dev ntfs-3g
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install system dependencies."
        exit 1
    fi
fi
echo "System dependencies installed successfully."


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
# CONFIGURE WIFI
################################################################################

# Console output
echo "Installing WiFi..."

# Update package lists
# Dont. Takes much time.
#sudo apt-get update

# Install usb-modeswitch
sudo apt-get install -y usb-modeswitch || {
    echo "Failed to install usb-modeswitch."
    exit 1
}

#install eject package for safely ejecting the AIC8800DC after flashing the firmware
sudo apt-get install -y eject || {
    echo "Failed to install eject."
    exit 1
}


# ------------------------------------------------------------------
# Detect which USB Wi-Fi dongle is attached
# ------------------------------------------------------------------
echo "Detecting WiFi chip..."

# 1) Realtek RTL8188GU (needs firmware only)
device_info_rtl=$(lsusb | grep -i "RTL8188GU")
TARGET_FW="/lib/firmware/rtlwifi/rtl8710bufw_SMIC.bin"

# 2) AIC8800DC appears first as mass-storage (id 0x5721)
device_info_aic_mass_storage=$(lsusb | grep -i "a69c:5721")

# 3) AIC8800DC already switched to Wi-Fi mode (id 0x0013)
device_info_aic_wifi=$(lsusb | grep -i "2604:0013")

# Package/-deb file for AIC8800DC
AIC_PKG="aic8800-dkms.deb"
AIC_DEB="${WIFI_DIR}/${AIC_PKG}.deb"

# RTL8188GU  --------------------------------------------------------
if [ -n "$device_info_rtl" ]; then
    echo "RTL8188GU detected."
    vendor_id=$(echo "$device_info_rtl" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_rtl" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Switch device into WLAN mode
    sudo usb_modeswitch -v "$vendor_id" -p "$product_id" -J

    # Copy firmware only if it is not already present
    if [ -f "$TARGET_FW" ]; then
        echo "Firmware already present – skipping copy."
    else
        if [ ! -f "${WIFI_DIR}/rtl8710bufw_SMIC.bin" ]; then
            echo "Error: firmware file ${WIFI_DIR}/rtl8710bufw_SMIC.bin not found."
            exit 1
        fi
        sudo cp "${WIFI_DIR}/rtl8710bufw_SMIC.bin" "$TARGET_FW" || {
            echo "Error: failed to copy firmware."; exit 1; }
    fi
    echo "WiFi setup for RTL8188GU finished."

# AIC8800DC shows up as mass-storage  -------------------------------
elif [ -n "$device_info_aic_mass_storage" ]; then
    echo "AIC8800DC detected as mass-storage device."
    vendor_id=$(echo "$device_info_aic_mass_storage" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_aic_mass_storage" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Switch device from storage to Wi-Fi mode
    sudo usb_modeswitch -KQ -v "$vendor_id" -p "$product_id"

    # Create udev rule so that future plug-ins are switched automatically
    echo "Creating udev rule for automatic mode-switch..."
    echo "ACTION==\"add\", ATTR{idVendor}==\"${vendor_id}\", ATTR{idProduct}==\"${product_id}\", RUN+=\"/usr/sbin/usb_modeswitch -v ${vendor_id} -p ${product_id} -KQ\"" \
        | sudo tee /etc/udev/rules.d/99-usb_modeswitch.rules >/dev/null

    # Reload udev rules immediately
    sudo udevadm control --reload-rules

    # Install driver only if it is NOT already present
    if dpkg -s "$AIC_PKG" >/dev/null 2>&1; then
        echo "$AIC_PKG is already installed – skipping."
    else
        echo "Installing package $AIC_PKG..."
        if [ ! -f "$AIC_DEB" ]; then
            echo "Error: driver package $AIC_DEB not found."
            exit 1
        fi
        sudo dpkg -i "$AIC_DEB" || { echo "Error: dpkg failed."; exit 1; }
    fi
    echo "WiFi setup for AIC8800DC finished."

# AIC8800DC already in Wi-Fi mode  ---------------------------------
elif [ -n "$device_info_aic_wifi" ]; then
    echo "AIC8800DC detected in Wi-Fi mode."
    vendor_id=$(echo "$device_info_aic_wifi" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_aic_wifi" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Install driver only if it is NOT already present
    if dpkg -s "$AIC_PKG" >/dev/null 2>&1; then
        echo "$AIC_PKG is already installed – skipping."
    else
        echo "Installing package $AIC_PKG..."
        if [ ! -f "$AIC_DEB" ]; then
            echo "Error: driver package $AIC_DEB not found."
            exit 1
        fi
        sudo dpkg -i "$AIC_DEB" || { echo "Error: dpkg failed."; exit 1; }
    fi
    echo "WiFi setup for AIC8800DC finished."

# No supported device found  ---------------------------------------
else
    echo "No supported WiFi chip detected. Please make sure the dongle is connected."
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
    echo "Error: File ${FREEDI_DIR}/helpers/usbmounter.sh does not exist. Aborting."
    exit 1
fi
chmod +x "${FREEDI_DIR}/helpers/usbmounter.sh"
if [ $? -ne 0 ]; then
    echo "Error: Failed to set executable permission for usbmounter.sh. Aborting."
    exit 1
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
    echo "Error: Source file ${FREEDI_DIR}/helpers/FreeDi.service does not exist. Aborting."
    exit 1
fi
sudo cp "${FREEDI_DIR}/helpers/FreeDi.service" /etc/systemd/system/FreeDi.service
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy FreeDi.service to /etc/systemd/system/. Aborting."
    exit 1
fi
echo "FreeDi.service moved to /etc/systemd/system/"

# Setting current user in FreeDi.service
echo "Setting user to $USER_NAME in FreeDi.service"
if [ ! -f /etc/systemd/system/FreeDi.service ]; then
    echo "Error: File /etc/systemd/system/FreeDi.service does not exist. Aborting."
    exit 1
fi
sudo sed -i "s/{{USER}}/${USER_NAME}/g" /etc/systemd/system/FreeDi.service
if [ $? -ne 0 ]; then
    echo "Error: Failed to replace user in /etc/systemd/system/FreeDi.service. Aborting."
    exit 1
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
    echo "Error: Source file ${FREEDI_DIR}/helpers/AutoFlasher.service does not exist. Aborting."
    exit 1
fi
sudo cp "${FREEDI_DIR}/helpers/AutoFlasher.service" /etc/systemd/system/AutoFlasher.service
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy AutoFlasher.service to /etc/systemd/system/. Aborting."
    exit 1
fi
echo "AutoFlasher.service installed!"

# Setting current user in AutoFlasher.service
echo "Setting user to $USER_NAME in AutoFlasher.service"

if [ ! -f "/etc/systemd/system/AutoFlasher.service" ]; then
    echo "Error: File /etc/systemd/system/AutoFlasher.service does not exist. Aborting."
    exit 1
fi
sudo sed -i "s/{{USER}}/${USER_NAME}/g" /etc/systemd/system/AutoFlasher.service
if [ $? -ne 0 ]; then
    echo "Error: Failed to replace user in /etc/systemd/system/AutoFlasher.service. Aborting."
    exit 1
fi


# Make the script executable
if [ ! -f "${FREEDI_DIR}/helpers/klipper_auto_flasher.sh" ]; then
    echo "Error: File ${FREEDI_DIR}/helpers/klipper_auto_flasher.sh does not exist. Aborting."
    exit 1
fi
chmod +x "${FREEDI_DIR}/helpers/klipper_auto_flasher.sh"
if [ $? -ne 0 ]; then
    echo "Error: Failed to set executable permission for klipper_auto_flasher.sh. Aborting."
    exit 1
fi

# Enable AutoFlasher.service to start at boot
echo "Enabling AutoFlasher.service to start at boot..."
sudo systemctl enable AutoFlasher.service
echo "AutoFlasher.service enabled to start at boot!"

# Make hid-flash executable
echo "Making hid-flash executable..."
if [ ! -f "${FREEDI_DIR}/helpers/hid-flash" ]; then
    echo "Error: File ${FREEDI_DIR}/helpers/hid-flash does not exist. Aborting."
    exit 1
fi
chmod +x "${FREEDI_DIR}/helpers/hid-flash"
if [ $? -ne 0 ]; then
    echo "Error: Failed to set executable permission for hid-flash. Aborting."
    exit 1
fi

echo "AutoFlasher.service installed!"
################################################################################
# FINALIZE INSTALLATION
################################################################################

echo "Reloading systemd manager configuration..."
sudo systemctl daemon-reload
echo "systemd manager configuration reloaded."

echo "Starting FreeDi service..."
sudo systemctl start FreeDi.service
echo "FreeDi service started!"

echo ""
echo "=================================================================================="
echo "Setup complete!"
echo "Please restart your system for the changes to take effect."
echo "=================================================================================="
