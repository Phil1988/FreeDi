#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' install.sh



# Ask the user if they use the stock Mainboard
echo "Do you use the stock Mainboard? (y/n)"
read RESPONSE

if [ "$RESPONSE" = "n" ]; then
	echo "As you have modified hardware, please go to the https://github.com/Phil1988/FreeDi and open a ticket to get help."
	exit 1
else
    echo "Starting the installation..."
fi


# Path to config.ini-file
config_file="config.ini"

# Get the printer model
printer_model=$(grep -oP '^printer_model\s*=\s*\K.+' "$config_file")

# Check printer model value
if [ -n "$printer_model" ]; then
    echo "Your printer model is: $printer_model"
else
    echo "Error: Couldnt find printer_model in config.ini. Make sure to add it to your printer.cfg after update has been completed."
fi


#Set variables
SERVICE="X3seriesLCD.service"
BKDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
X3DIR="${BKDIR}/X3seriesLCD"
LCDFIRMWAREDIR="${BKDIR}/screen_firmwares"

# Checking out only the necessary folders
git sparse-checkout add FreeDiLCD/
git sparse-checkout add screen_firmwares/
git sparse-checkout add klipper_module/


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

# Creating a symbolic link for freedi.py module to the Klipper extras directory
echo "Creating a symbolic link for $MODULE_NAME to $KLIPPER_EXTRAS_DIR..."
#cp "$REPO_MODULE_PATH" "$KLIPPER_EXTRAS_DIR"
ln -sf /home/${USER_NAME}/FreeDi/klipper_module/freedi.py /home/${USER_NAME}/klipper/klippy/extras/

if [ $? -eq 0 ]; then
    echo "Successfully installed $MODULE_NAME to $KLIPPER_EXTRAS_DIR."
else
    echo "Error: Failed to copy $MODULE_NAME to $KLIPPER_EXTRAS_DIR."
    exit 1
fi



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
		exit 1
	fi
else
	#echo "Service $SERVICE is not available." >&2
	exit 1
fi


# Add update entry to moonraker conf
MOONFILE="$HOME/printer_data/config/moonraker.conf"

# Check if the file exists
if [ -f "$MOONFILE" ]; then
	echo "File exists: $MOONFILE"
	
	# Check if the line [update_manager freeDi] exists
	if grep -q "^\[update_manager freeDi\]" "$MOONFILE"; then
		echo "The section [update_manager freeDi] already exists in the file."
	else
		echo "The section [update_manager freeDi] does not exist. Adding it to the end of the file."
		
		# Append the block to the end of the file
		cat <<EOL >> "$MOONFILE"

[update_manager freeDi]
type: git_repo
path: ~/freeDi
channel: dev
origin: https://github.com/Phil1988/FreeDi
virtualenv: ~/klippy-env
requirements: requirements.txt
install_script: install.sh
is_system_service: False
managed_services: klipper
info_tags:
	desc=FreeDi LCD Screen
	sparse_dirs:
	- X3seriesLCD
	- screen_firmwares
EOL

		echo "The section [update_manager freeDi] has been added to the file."
	fi
else
	echo "File does not exist: $MOONFILE"
	exit 1
fi


# Define variables
USER_NAME=$(whoami)
NM_CONF_FILE="/etc/NetworkManager/NetworkManager.conf"

# Set ownership and permissions for the ~/X3seriesLCD directory
echo "Setting ownership and permissions for ~/X3seriesLCD"
sudo chown -R $USER_NAME:$USER_NAME ${BKDIR}/X3seriesLCD
sudo chmod -R 755 ${BKDIR}/X3seriesLCD
echo "Ownership and permissions set"



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
echo "FreeDi.service is now executable!"

# Stopping olt X3seriesLCD service
echo "Stopping X3seriesLCD.service..."
sudo systemctl stop X3seriesLCD.service

# Removing old X3seriesLCD service
echo "Removing old X3seriesLCD.service..."
sudo rm /etc/systemd/system/X3seriesLCD.service
echo "X3seriesLCD.service removed!"

# Move new FreeDi.service to systemd directory
echo "Moving new FreeDi.service to /etc/systemd/system/"
sudo cp ${X3DIR}/FreeDi.service /etc/systemd/system/FreeDi.service
echo "FreeDi.service moved to /etc/systemd/system/"



# Set correct permissions for FreeDi.service
echo "Setting permissions for /etc/systemd/system/FreeDi.service"
#sudo chmod 644 /etc/systemd/system/FreeDi.service
echo "Permissions set to 644 for /etc/systemd/system/FreeDi.service!"

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
