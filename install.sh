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
	if sudo systemctl stop "$SERVICE"; then
		echo "Service $SERVICE stopped successfully."
	else
		echo "Failed to stop service $SERVICE." >&2
		#exit 1
	fi
else
	echo "Service $SERVICE is not available." >&2
	#exit 1
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
echo "Setting ownership and permissions for ~/FreeDi"
sudo chown -R $USER_NAME:$USER_NAME ${BKDIR}/FreeDi
sudo chmod -R 755 ${BKDIR}/FreeDi
echo "Ownership and permissions set"



# Autostart the program
echo "Installing the service to starts this program automatically at boot time..."

# Make start.py executable
echo "Making start.py executable..."
sudo chmod +x ${X3DIR}/start.py
echo "start.py is now executable!"

# Make FreeDi.service file executable
echo "Making FreeDi.service executable..."
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

# Install required packages
#echo "Installing required packages for input shaping..."
#sudo apt install -y python3-numpy python3-matplotlib libatlas-base-dev libopenblas-dev

# Install numpy using pip within the virtual environment
#echo "Installing numpy in the virtual environment..."
#~/klippy-env/bin/pip install -v numpy


# Console output
echo "Setup complete!"
echo "Please restart your system for the changes to take effect."
