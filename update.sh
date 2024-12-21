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
echo "Do you have a system where the stock LCD screen runs the FreeDi or X3seriesLCD on a firmware up to v1.03? (y/n)"
read RESPONSE

if [ "$RESPONSE" = "n" ]; then
	echo "This update script is only for users that have already a working setup with FreeDi/X3seriesLCD up to v1.03."
	exit 1
else
    echo "Ok! Starting the update process..."
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

# Variables for the Klipper module
KLIPPER_EXTRAS_DIR="$HOME/klipper/klippy/extras"
MODULE_NAME="freedi.py"

# Ensure the Klipper extras directory exists
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
else
    echo "Error: Failed to restart Klipper service."
    exit 1
fi

###### Setup Python environment ######

# Activate the Klipper virtual environment and install required Python packages
echo "Activating Klipper virtual environment and installing Python packages..."

# Set Python path to Klipper environment
KENV="${HOME}/klippy-env"
PYTHON_EXEC="$KENV/bin/python"

# Check if the Klipper environment exists
if [ ! -d "$KENV" ]; then
    echo "Error: Klipper environment not found. Cannot continue installation."
    exit 1
fi

source "$KENV/bin/activate"
pip install --upgrade numpy matplotlib
if [ $? -ne 0 ]; then
    echo "Error: Failed to install Python packages."
    deactivate
    exit 1
fi
deactivate

# Verify Python version
PYTHON_V=$($PYTHON_EXEC -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "Klipper environment Python version: $PYTHON_V"

# Install additional Python requirements from requirements.txt
echo "Installing Python requirements from requirements.txt..."
"$KENV/bin/pip" install -r "${BKDIR}/requirements.txt" || {
    echo "Error: Failed to install Python requirements."
    exit 1
}
echo "Python requirements installed successfully."

###### Install system dependencies ######

# Installing required packages for input shaping (if not already installed)
echo "Installing required packages for input shaping (if not already installed)..."

sudo apt install -y libatlas-base-dev libopenblas-dev
if [ $? -ne 0 ]; then
    echo "Error: Failed to install system dependencies."
    exit 1
fi
echo "System dependencies installed successfully."

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
	desc=FreeDi LCD
	sparse_dirs:
	- FreeDiLCD
	- screen_firmwares
EOL
        echo "Update manager configuration for [update_manager freeDi] added successfully."
    else
        echo "FreeDi update manager configuration already exists in Moonraker."
    fi
else
    echo "Error: Moonraker configuration file not found."
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

###### Setup FreeDi ######

# Stop and disable old X3seriesLCD service
echo "Stopping and disabling old X3seriesLCD service..."
sudo systemctl stop X3seriesLCD.service
sudo systemctl disable X3seriesLCD.service
echo "X3seriesLCD service stopped and disabled."

# Removing old X3seriesLCD service
echo "Removing old X3seriesLCD.service..."
sudo rm /etc/systemd/system/X3seriesLCD.service
echo "X3seriesLCD.service removed!"

# Removing old X3seriesLCD directory
echo "Removing old X3seriesLCD directory..."
sudo rm -rf $HOME/X3seriesLCD
echo "X3seriesLCD directory removed!"

# Autostart the program
echo "Installing the service to starts this program automatically at boot time..."

# Set ownership and permissions for the ~/FreeDi directory
echo "Setting ownership and permissions for ~/FreeDi"
sudo chown -R $USER_NAME:$USER_NAME ${BKDIR}
sudo chmod -R 755 ${BKDIR}
echo "Ownership and permissions set"

# Make start.py executable
echo "Making start.py executable..."
sudo chmod +x ${FREEDI_LCD_DIR}/start.py
echo "start.py is now executable!"

# Move new FreeDi.service to systemd directory
echo "Moving new FreeDi.service to /etc/systemd/system/"
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
