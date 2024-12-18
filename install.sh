#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' install.sh

#Set variables
USER_NAME=$(whoami)
SERVICE="FreeDi.service"
BKDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
X3DIR="${BKDIR}/FreeDiLCD"
LCDFIRMWAREDIR="${BKDIR}/screen_firmwares"

# Ask the user if they use the stock Mainboard
echo "Do you use the stock Mainboard? (y/n)"
read RESPONSE

if [ "$RESPONSE" = "n" ]; then
	echo "As you have modified hardware, please go to the https://github.com/Phil1988/FreeDi and open a ticket to get help."
	exit 1
else
    echo "Starting the installation..."
fi

# Creating klipper freedi section
USER_NAME="${USER_NAME:-mks}"  # Default to 'mks' if USER_NAME is not set
CONFIG_FILE="/home/$USER_NAME/printer_data/config/printer.cfg"
FREEDI_SECTION="[freedi]"
SAVE_CONFIG_MARKER="#*# <---------------------- SAVE_CONFIG ---------------------->"

# Prompt user for printer model
echo "Please input the printer model (options: x-max3, x-plus3):"
read -r printer_model

# Validate input
if [[ "$printer_model" != "x-max3" && "$printer_model" != "x-plus3" ]]; then
    echo "Error: Invalid printer model. Allowed values are: x-max3, x-plus3."
    exit 1
fi

# Replacement content for [freedi] block
FREEDI_CONTENT="[freedi]
# Printer model. Currently supported: x-smart3, x-plus3, x-max3, q1-pro, plus4
printer_model: $printer_model
# Baud rate for serial communication. Stock mainboard with standard firmware: 921600 | Legacy firmware: 115200
baudrate: 921600
# Serial port for the LCD. Stock: /dev/ttyS1 | USB<->TTL adapter: /dev/ttyUSB0 | BTT Manta M5P: /dev/ttyS0
serial_port: /dev/ttyS1
# URL of the printer service
url: 127.0.0.1
# API key for the printer
api_key: XXXXXX
# Path to the Klippy socket file
klippy_socket: /home/$USER_NAME/printer_data/comms/klippy.sock
# Specify if you want to use the stable or beta channel. Caution: beta firmwares have more potential to have bugs.
channel: stable
"

# Step 1: Remove old [freedi] block if it exists
if grep -q "^\[freedi\]" "$CONFIG_FILE"; then
    sed -i '/^\[freedi\]/,/^\[.*\]\|#*# <---------------------- SAVE_CONFIG ---------------------->/c\
'"$FREEDI_CONTENT" "$CONFIG_FILE"
    echo "[freedi] section replaced successfully."
    exit 0
fi

# Step 2: Insert before SAVE_CONFIG marker
if grep -q "$SAVE_CONFIG_MARKER" "$CONFIG_FILE"; then
    sed -i "/$SAVE_CONFIG_MARKER/i $FREEDI_CONTENT" "$CONFIG_FILE"
    echo "[freedi] section inserted before SAVE_CONFIG marker."
    exit 0
fi

# Step 3: If neither [freedi] nor SAVE_CONFIG marker found, throw an error
echo "Error: Neither [freedi] section nor SAVE_CONFIG marker found in the configuration file."
exit 1


# Varialbles for the klipper module
KLIPPER_EXTRAS_DIR="$HOME/klipper/klippy/extras"
MODULE_NAME="freedi.py"
REPO_MODULE_PATH="./klipper_module/$MODULE_NAME"

# Ensure the Klipper extras directory exists
if [ ! -d "$KLIPPER_EXTRAS_DIR" ]; then
    echo "Error: Klipper extras directory not found at $KLIPPER_EXTRAS_DIR."
    echo "Make sure Klipper is installed correctly."
    exit 1
fi

# Copy the freedi.py module to the Klipper extras directory
echo "Copying $MODULE_NAME to $KLIPPER_EXTRAS_DIR..."
cp "$REPO_MODULE_PATH" "$KLIPPER_EXTRAS_DIR"

if [ $? -eq 0 ]; then
    echo "Successfully installed $MODULE_NAME to $KLIPPER_EXTRAS_DIR."
else
    echo "Error: Failed to copy $MODULE_NAME to $KLIPPER_EXTRAS_DIR."
    exit 1
fi

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



#doing homework
git sparse-checkout add FreeDiLCD/
git sparse-checkout add screen_firmwares/

# Set python path to klipper env
KENV="${HOME}/klippy-env"
PYTHON_EXEC="$KENV/bin/python"

if [ ! -d "$KENV" ]; then
	echo "Klippy env doesn't exist so I can't continue installation..."
	exit 1
fi

PYTHON_V=$($PYTHON_EXEC -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "Klipper environment python version: $PYTHON_V"

echo "Arranging python requirements..."
	"${KENV}/bin/pip" install -r "${BKDIR}/requirements.txt"
	
# Install required packages for input shaping
echo "Installing required packages for input shaping..."
sudo apt install -y libatlas-base-dev libopenblas-dev

# LCD firmware logic

# Check if the service exists
if systemctl list-units --type=service --all | grep "$SERVICE"; then
	#echo "Service $SERVICE is available."
	
	# Stop the service
	if systemctl stop "$SERVICE"; then
		echo "Service $SERVICE stopped successfully."
	else
		echo "Failed to stop service $SERVICE." >&2
		#exit 1
	fi
else
	echo "Service $SERVICE is not available." >&2
	#exit 1
fi

echo "Checking LCD firmware version"
LCD_SERIAL_PORT="/dev/ttyS1"
LCD_SERIAL_INIT_BAUD=0
LCD_SERIAL_FLASH_BAUD=921600
LCD_FIRMWARE="${LCDFIRMWAREDIR}/X3seriesLCD_firmware_v1.03.tft"

#$PYTHON_EXEC "${X3DIR}/lcd_helper.cpython-311-aarch64-linux-gnu.so" ${LCD_FIRMWARE} ${LCD_SERIAL_PORT} ${LCD_SERIAL_INIT_BAUD} ${LCD_SERIAL_FLASH_BAUD}

if [ $? -ne 0 ]; then
	echo "Error: Firmware update failed!"
	# You can handle the failure here (e.g., logging, retrying, etc.)
	exit 1
else
	echo "Firmware up to date"
fi

# Add update entry to moonraker conf
MOONFILE="$HOME/printer_data/config/moonraker.conf"

# Check if the file exists
if [ -f "$MOONFILE" ]; then
	echo "File exists: $MOONFILE"
	
	# Check if the line [update_manager freeDi] exists
	if grep -q "^\[update_manager FreeDi\]" "$MOONFILE"; then
		echo "The section [update_manager FreeDi] already exists in the file."
	else
		echo "The section [update_manager FreeDi] does not exist. Adding it to the end of the file."
		
		# Append the block to the end of the file
		cat <<EOL >> "$MOONFILE"

# FreeDi update_manager entry
[update_manager FreeDi]
type: git_repo
path: ~/FreeDi
channel: dev
origin: https://github.com/Phil1988/FreeDi
virtualenv: ~/klippy-env
requirements: requirements.txt
install_script: install.sh
managed_services: FreeDi
info_tags:
	desc=FreeDi LCD Screen
	sparse_dirs:
	- FreeDiLCD
	- screen_firmwares
EOL

		echo "The section [update_manager freeDi] has been added to the file."
	fi
else
	echo "File does not exist: $MOONFILE"
	exit 1
fi

# Define the file path
file="/home/${USER_NAME}/printer_data/moonraker.asvc"

# Check if the file exists
if [ -f "$file" ]; then
    # Search for the string "FreeDi" in the file
    if grep -Fxq "FreeDi" "$file"; then
        echo "\"FreeDi\" is already present in the moonraker.asvc file. No changes made."
    else
        # Append "FreeDi" to the end of the file
        echo "FreeDi" >> "$file"
        echo "\"FreeDi\" has been added to the moonraker.asvc file."
    fi
else
    echo "moonraker.asvc file not found: $file"
fi

# Define variables
NM_CONF_FILE="/etc/NetworkManager/NetworkManager.conf"

# Set ownership and permissions for the ~/FreeDiLCD directory
echo "Setting ownership and permissions for ~/FreeDiLCD"
sudo chown -R $USER_NAME:$USER_NAME ${BKDIR}/FreeDiLCD
sudo chmod -R 755 ${BKDIR}/FreeDiLCD
echo "Ownership and permissions set"

# Console output
#echo "Installing python3-pip git (necessary to run the program)..."
# Install python3-pip and git
#sudo apt-get install -y python3-pip git
#echo "python3-pip git install done!"

# Console output
#echo "Installing pyserial (necessary for communication to the display)..."
# Install pyserial
#sudo apt install python3-serial
#echo "pyserial install done!"

# Console output
#echo "Installing python3-requests (necessary for communication with moonraker)..."
# Install python3-requests
#sudo apt-get install -y python3-requests
#echo "python3-requests install done!"

# # Console output
# echo "Installing Pillow (necessary to create thumbnail)..."
# # Install Pillow
# sudo apt install python3-pil
# echo "Pillow install done!"

# Console output
echo "Setup dtbo for serial communication..."
# Install dtbo file for serial communication
sudo cp ${X3DIR}/dtbo/rockchip-mkspi-uart1.dtbo /boot/dtb/rockchip/overlay/
echo "dtbo install done!"

# Stating the modification of the armbianEnv.txt
echo "Customise the armbianEnv.txt file for serial communication..."
# The file to check
FILE="/boot/armbianEnv.txt"
# The entry to search for
SEARCH_STRING="overlays="
# The new line to add or replace
NEW_LINE="overlays=mkspi-uart1"

# Check if the file exists
if [ ! -f "$FILE" ]; then
	echo "File $FILE does not exist."
	exit 1
fi

# Check if the file contains the search string and perform the corresponding action
if sudo grep -q "^$SEARCH_STRING" "$FILE"; then
	echo "Line found. Replacing the line."
	sudo sed -i "s/^$SEARCH_STRING.*/$NEW_LINE/" "$FILE"
else
	echo "Line not found. Adding the line."
	echo "$NEW_LINE" | sudo tee -a "$FILE" > /dev/null
fi

echo "armbianEnv.txt customization completed."

# Console output
echo "Installing wifi ..."
# Update package lists
sudo apt-get update
# Install usb-modeswitch
sudo apt-get install -y usb-modeswitch

# Find vendor_id and product_id for RTL8188GU
echo "Finding vendor_id and product_id for RTL8188GU"
device_info=$(lsusb | grep -i "RTL8188GU")
if [ -n "$device_info" ]; then
	vendor_id=$(echo $device_info | awk '{print $6}' | cut -d: -f1)
	product_id=$(echo $device_info | awk '{print $6}' | cut -d: -f2)
	echo "vendor_id: $vendor_id, product_id: $product_id"
	
	# Configure the USB WLAN dongle
	sudo usb_modeswitch -v $vendor_id -p $product_id -J
	# Copy the firmware file
	sudo cp ${X3DIR}/wifi/rtl8710bufw_SMIC.bin /lib/firmware/rtlwifi/
	echo "wifi install done!"
else
	echo "RTL8188GU not found. Please ensure the device is connected."
fi

# Console output
echo "Changing permissions to enable nmcli commands without sudo (necessary for setting wifi via screen)..."


# Add the user to the netdev group
echo "Adding the user ${USER_NAME} to the 'netdev' group..."
sudo usermod -aG netdev $USER_NAME

# Check if the auth-polkit line already exists in the config file
# Add the auth-polkit=false line after plugins=ifupdown,keyfile in the [main] section
if grep -q '^\[main\]' "$NM_CONF_FILE"; then
	if ! grep -q '^auth-polkit=false' "$NM_CONF_FILE"; then
		echo "Adding 'auth-polkit=false' to ${NM_CONF_FILE}..."
		sudo sed -i '/^plugins=ifupdown,keyfile/a auth-polkit=false' "$NM_CONF_FILE"
	else
		echo "'auth-polkit=false' is already present in ${NM_CONF_FILE}."
	fi
else
	echo "The [main] section was not found in ${NM_CONF_FILE}."
fi

# Display information
echo "User ${USER_NAME} has been successfully configured to run nmcli commands without sudo."


# Autostart the program
echo "Installing the service to starts this program automatically at boot time..."

# Make start.py executable
echo "Making start.py executable..."
sudo chmod +x ${X3DIR}/start.py
echo "start.py is now executable!"

# Make FreeDi.service file executable
echo "Making FreeDi.service executable..."
#sudo chmod +x ${X3DIR}/FreeDi.service
echo "FreeDi.service is now executable!"

# Move FreeDi.service to systemd directory
echo "Moving FreeDi.service to /etc/systemd/system/"
sudo cp ${X3DIR}/FreeDi.service /etc/systemd/system/FreeDi.service
echo "FreeDi.service moved to /etc/systemd/system/"

# Set correct permissions for FreeDi.service
echo "Setting permissions for /etc/systemd/system/FreeDi.service"
#sudo chmod 644 /etc/systemd/system/FreeDi.service
echo "Permissions set to 644 for /etc/systemd/system/FreeDi.service!"

# Reload systemd manager configuration
echo "Reloading systemd manager configuration..."
systemctl daemon-reload
echo "systemd manager configuration reloaded!"

# Enable FreeDi.service to start at boot
echo "Enabling FreeDi.service to start at boot..."
systemctl enable FreeDi.service
echo "FreeDi.service enabled to start at boot!"

# Start FreeDiLCD.service
echo "Starting FreeDi.service..."
systemctl start FreeDi.service
echo "FreeDiLCD.service started!"

# Update package lists
echo "Updating package lists..."
sudo apt update -y

# Install required packages
#echo "Installing required packages for input shaping..."
#sudo apt install -y python3-numpy python3-matplotlib libatlas-base-dev libopenblas-dev

# Install numpy using pip within the virtual environment
#echo "Installing numpy in the virtual environment..."
#~/klippy-env/bin/pip install -v numpy


# Console output
echo "Setup complete!"
echo "Please restart your system for the changes to take effect."
