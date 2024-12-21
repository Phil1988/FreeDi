#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' install.sh

# Set variables
USER_NAME=$(whoami)
SERVICE="FreeDi.service"
BKDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
FREEDI_LCD_DIR="${BKDIR}/FreeDiLCD"
REPO_MODULE_DIR="${BKDIR}/klipper_module"
LCD_FIRMWARE_DIR="${BKDIR}/screen_firmwares"

# Ask the user if they use the stock Mainboard
echo "Do you use the stock Mainboard? (y/n)"
read RESPONSE

if [ "$RESPONSE" = "n" ]; then
	echo "As you have modified hardware, please go to the https://github.com/Phil1988/FreeDi and open a ticket to get help."
	exit 1
else
    echo "Starting the installation..."
fi

# Check if the script is run inside a Git repository
if [ ! -d ".git" ]; then
    echo "Error: Not a git repository. Please initialize the repository first."
    exit 1
fi

# Sparse checkout only the required folders
git sparse-checkout add FreeDiLCD/
git sparse-checkout add screen_firmwares/
git sparse-checkout add klipper_module/


###### Installing klipper module ######

# Varialbles for the klipper module
KLIPPER_EXTRAS_DIR="$HOME/klipper/klippy/extras"
MODULE_NAME="freedi.py"

# Ensure if the Klipper extras directory exists
if [ ! -d "$KLIPPER_EXTRAS_DIR" ]; then
    echo "Error: Klipper extras directory not found at $KLIPPER_EXTRAS_DIR."
    echo "Make sure Klipper is installed correctly."
    exit 1
fi

# Create a symbolic link for freedi.py module to the Klipper extras directory
echo "Creating a symbolic link for $MODULE_NAME from $REPO_MODULE_DIR to $KLIPPER_EXTRAS_DIR..."
ln -sf "${REPO_MODULE_DIR}/freedi.py" "${KLIPPER_EXTRAS_DIR}/freedi.py"

if [ $? -eq 0 ]; then
    echo "Successfully installed $MODULE_NAME to $KLIPPER_EXTRAS_DIR."
else
    echo "Error: Failed to create a symbolic link for $MODULE_NAME."
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


###### Setup python environment ######

# Activate the Klipper virtual environment and install required Python packages
echo "Activating Klipper virtual environment and installing Python packages..."

# Set python path to klipper env
KENV="${HOME}/klippy-env"
PYTHON_EXEC="$KENV/bin/python"

if [ ! -d "$KENV" ]; then
	echo "Klippy env doesn't exist so I can't continue installation..."
	exit 1
fi

source ~/klippy-env/bin/activate
pip install --upgrade numpy matplotlib
deactivate
echo "Python packages numpy and matplotlib installed and virtual environment deactivated."

PYTHON_V=$($PYTHON_EXEC -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "Klipper environment python version: $PYTHON_V"

# Arrange Python requirements from requirements.txt
echo "Arranging Python requirements..."
"${KENV}/bin/pip" install -r "${BKDIR}/requirements.txt" || {
    echo "Failed to install Python requirements."
    exit 1
}
echo "Python requirements installed from requirements.txt."


###### Setup necessary dependencies for FreeDi and input shaping ######

# Installing required packages for input shaping (if not already installed)
echo "Installing required packages for input shaping (if not already installed)..."

sudo apt install -y libatlas-base-dev libopenblas-dev
if [ $? -ne 0 ]; then
    echo "Error: Failed to install system dependencies."
    exit 1
fi
echo "System dependencies installed successfully."


###### Stop FreeDi service ######

# Stop FreeDi service
echo "Stopping FreeDi service..."

# Check if the service exists
if systemctl list-units --type=service --all | grep "$SERVICE"; then
	#echo "Service $SERVICE is available."
	
	# Stop the service
	if systemctl stop "$SERVICE"; then
		echo "Service $SERVICE stopped successfully."
	else
		echo "Failed to stop service $SERVICE." >&2
		exit 1
	fi
else
	echo "Service $SERVICE not found. Please ensure it is installed or the name is correct." >&2
	exit 1
fi


###### Setup Moonraker update manager ######

# Adding FreeDi section to moonraker update manager
echo "Adding FreeDi section to moonraker update manager..."

# Add update entry to moonraker conf
MOONFILE="$HOME/printer_data/config/moonraker.conf"

# Check if the file exists
if [ -f "$MOONFILE" ]; then
	echo "Moonraker configuration file $MOONFILE found"
	
	# Check if the section [update_manager FreeDi] exists
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
	desc=FreeDi
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

# Permit Moonraker to restart FreeDi service
echo "Permit Moonraker to restart FreeDi service..."

# Define moonraker.asvc file path
file="$HOME/printer_data/moonraker.asvc"

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


###### Setup NetworkManager ######

# Console output
echo "Changing permissions to enable nmcli commands without sudo (necessary for setting wifi via screen)..."

# Define variables
NM_CONF_FILE="/etc/NetworkManager/NetworkManager.conf"

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


###### Setup Wifi ######

# Console output
echo "Installing WiFi..."

# Update package lists
sudo apt-get update

# Install usb-modeswitch
sudo apt-get install -y usb-modeswitch || {
    echo "Failed to install usb-modeswitch."
    exit 1
}

# Check for connected USB devices and identify the WiFi chip
echo "Detecting WiFi chip..."

# Find RTL8188GU device
device_info_rtl=$(lsusb | grep -i "RTL8188GU")

# Find AIC8800DC device
device_info_aic=$(lsusb | grep -i "a69c:5721")

if [ -n "$device_info_rtl" ]; then
    echo "RTL8188GU detected."
    vendor_id=$(echo $device_info_rtl | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo $device_info_rtl | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Configure the USB WLAN dongle
    sudo usb_modeswitch -v $vendor_id -p $product_id -J

    # Copy the firmware file
    sudo cp wifi/rtl8710bufw_SMIC.bin /lib/firmware/rtlwifi/
    echo "WiFi installation for RTL8188GU completed!"

elif [ -n "$device_info_aic" ]; then
    echo "AIC8800DC detected."
    vendor_id=$(echo $device_info_aic | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo $device_info_aic | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Configure the USB WLAN dongle for AIC8800DC
    sudo usb_modeswitch -KQ -v $vendor_id -p $product_id

    # Create udev rule to handle future connections automatically
    echo "Creating udev rule for AIC8800DC..."
    echo "ACTION==\"add\", ATTR{idVendor}==\"$vendor_id\", ATTR{idProduct}==\"$product_id\", RUN+=\"/usr/sbin/usb_modeswitch -v $vendor_id -p $product_id -KQ\"" | sudo tee /etc/udev/rules.d/99-usb_modeswitch.rules

    # Reload udev rules
    sudo udevadm control --reload
    echo "WiFi installation for AIC8800DC completed!"

else
    echo "No supported WiFi chip detected. Please ensure the device is connected."
fi


###### Setup FreeDi ######

# Set ownership and permissions for the ~/FreeDi directory
echo "Setting ownership and permissions for ~/FreeDi"
sudo chown -R $USER_NAME:$USER_NAME ${BKDIR}
sudo chmod -R 755 ${BKDIR}
echo "Ownership and permissions set"

# Autostart the program
echo "Installing the service to starts this program automatically at boot time..."

# Make start.py executable
echo "Making start.py executable..."
sudo chmod +x ${FREEDI_LCD_DIR}/start.py
echo "start.py is now executable!"

# Move FreeDi.service to systemd directory
echo "Moving FreeDi.service to /etc/systemd/system/"
sudo cp ${FREEDI_LCD_DIR}/FreeDi.service /etc/systemd/system/FreeDi.service
echo "FreeDi.service moved to /etc/systemd/system/"

# Reload systemd manager configuration
echo "Reloading systemd manager configuration..."
sudo systemctl daemon-reload
echo "systemd manager configuration reloaded!"

# Enable FreeDi.service to start at boot
echo "Enabling FreeDi.service to start at boot..."
sudo systemctl enable FreeDi.service
echo "FreeDi.service enabled to start at boot!"

# Start FreeDiLCD.service
echo "Starting FreeDi.service..."
sudo systemctl start FreeDi.service
echo "FreeDiLCD.service started!"

# Update package lists
echo "Updating package lists..."
sudo apt update -y

# Console output
echo "Setup complete!"
echo "Please restart your system for the changes to take effect."
