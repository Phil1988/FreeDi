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


###### Establishing freedi_update.sh ######

echo "Disabling freedi_update.sh git tracking for future modifications..."

if [ $? -eq 0 ]; then
    # Exclude freedi_update.sh from the FreeDi repo
    if ! grep -q "FreeDiLCD/freedi_update.sh" "${HOME}/FreeDi/.git/info/exclude"; then
        echo "FreeDiLCD/freedi_update.sh" >> "${HOME}/FreeDi/.git/info/exclude"
    fi
    echo "Successfully ignoring freedi_update.sh"
else
    echo "Error: Failed to ignore freedi_update.sh"
    exit 1
fi


echo "Removing freedi_update.sh from git index because it's already tracked..."
# sparse-checkout FreeDiLCD/freedi_update.sh
git sparse-checkout add FreeDiLCD/freedi_update.sh
# so it can be marked to be ignored
git rm --cached --sparse --skip-checks FreeDiLCD/freedi_update.sh 
echo "Local ignore setup completed. The file freedi_update.sh will now be ignored locally by git."

###### Sparse checkout required folders ######

# Sparse checkout only the required folders
echo "Sparse checkout only the required folders..."
git sparse-checkout add FreeDiLCD/
git sparse-checkout add helpers/
git sparse-checkout add klipper_module/
git sparse-checkout add mainboard_and_toolhead_firmwares/
git sparse-checkout add screen_firmwares/

# Configure git to fetch tags automatically, which is not done by default in sparse clones
echo "Configuring git to fetch tags automatically..."
git config remote.origin.fetch "+refs/tags/*:refs/tags/*"


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
ln -sf "${REPO_MODULE_DIR}/${MODULE_NAME}" "${KLIPPER_EXTRAS_DIR}/${MODULE_NAME}"

if [ $? -eq 0 ]; then
    # Exclude freedi.py from the Klipper repo as we introduce it and thus shouldn't be considered by the repo
    if ! grep -q "klippy/extras/${MODULE_NAME}" "${HOME}/klipper/.git/info/exclude"; then
        echo "klippy/extras/${MODULE_NAME}" >> "${HOME}/klipper/.git/info/exclude"
    fi
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


###### Setup serial port for LCD communication ######

# Console output
echo "Setup dtbo for serial communication..."
# Install dtbo file for serial communication
sudo cp $FREEDI_LCD_DIR/dtbo/rockchip-mkspi-uart1.dtbo /boot/dtb/rockchip/overlay/
echo "dtbo install done!"

# Stating the modification of the armbianEnv.txt
echo "Customize the armbianEnv.txt file for serial communication..."
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

echo "armbianEnv.txt file modified successfully!"


###### Setup printhead serial port to printer.cfg ######

# Define printer.cfg path
PRINTER_CONFIG="$HOME/printer_data/config/printer.cfg"

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

            # Use sed to update the serial line only within the [mcu MKS_THR] section
            sudo sed -i "/\[mcu MKS_THR\]/,/^\[/ {s|^serial:.*|serial: ${path}|}" "$PRINTER_CONFIG"
            
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

PYTHON_V=$($PYTHON_EXEC -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "Klipper environment python version: $PYTHON_V"

# Arrange Python requirements from requirements.txt
echo "Arranging Python requirements..."
"${KENV}/bin/pip" install --upgrade pip 
"${KENV}/bin/pip" install -r "${BKDIR}/requirements.txt" || {
    echo "Failed to install Python requirements."
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

# Find AIC8800DC as mass storage device
device_info_aic_mass_storage=$(lsusb | grep -i "a69c:5721")

# Find AIC8800DC as wifi device
device_info_aic_wifi=$(lsusb | grep -i "2604:0013")

if [ -n "$device_info_rtl" ]; then
    echo "RTL8188GU detected."
    vendor_id=$(echo $device_info_rtl | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo $device_info_rtl | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Configure the USB WLAN dongle
    sudo usb_modeswitch -v $vendor_id -p $product_id -J

    # Copy the firmware file
    sudo cp $FREEDI_LCD_DIR/wifi/rtl8710bufw_SMIC.bin /lib/firmware/rtlwifi/
    echo "WiFi installation for RTL8188GU completed!"


elif [ -n "$device_info_aic_mass_storage" ]; then
    echo "AIC8800DC detected as mass storage device."
    vendor_id=$(echo $device_info_aic_mass_storage | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo $device_info_aic_mass_storage | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Configure the USB WLAN dongle for AIC8800DC
    sudo usb_modeswitch -KQ -v $vendor_id -p $product_id

    # Create udev rule to handle future connections automatically
    echo "Creating udev rule for AIC8800DC..."
    echo "ACTION==\"add\", ATTR{idVendor}==\"$vendor_id\", ATTR{idProduct}==\"$product_id\", RUN+=\"/usr/sbin/usb_modeswitch -v $vendor_id -p $product_id -KQ\"" | sudo tee /etc/udev/rules.d/99-usb_modeswitch.rules

    # Reload udev rules
    sudo udevadm control --reload

    # Install the driver package
    echo "Installing driver package for AIC8800DC..."
    sudo dpkg -i ~/FreeDi/FreeDiLCD/wifi/ax300-wifi-adapter-linux-driver.deb

    echo "WiFi installation for AIC8800DC completed!"

elif [ -n "$device_info_aic_wifi" ]; then
    echo "AIC8800DC detected in wifi mode."
    vendor_id=$(echo $device_info_aic_wifi | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo $device_info_aic_wifi | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Install the driver package
    echo "Installing driver package for AIC8800DC..."
    sudo dpkg -i $FREEDI_LCD_DIR/wifi/ax300-wifi-adapter-linux-driver.deb

    echo "WiFi installation for AIC8800DC completed!"

else
    echo "No supported WiFi chip detected. Please ensure the device is connected."
fi


###### Setup usbmounter service for swappable usb drives ######

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
ExecStart=/home/'"$USER_NAME"'/FreeDi/helpers/usbmounter.sh '"$USER_NAME"' %i

EOL'
echo "Systemd service file created: /etc/systemd/system/usb-mount@.service"

# Make the script executable
echo "Making the usbmounter.sh executable..."
chmod +x /home/$USER_NAME/FreeDi/helpers/usbmounter.sh
echo "Script /home/$USER_NAME/FreeDi/helpers/usbmounter.sh is now executable."

# Reload udev and systemd
sudo udevadm control --reload
systemctl daemon-reload
echo "Udev and systemd have been reloaded."

echo "USB mounter service created successfully!"


###### Setup FreeDi ######

# Autostart the program
echo "Installing FreeDi service..."

# Stop running FreeDi service
echo "Stopping FreeDi service..."
sudo systemctl stop FreeDi.service
echo "FreeDi service stopped."

# Move FreeDi.service to systemd directory
echo "Moving FreeDi.service to /etc/systemd/system/"
sudo cp /home/$USER_NAME/FreeDi/helpers/FreeDi.service /etc/systemd/system/FreeDi.service
echo "FreeDi.service moved to /etc/systemd/system/"

# Setting current user in FreeDi.service
echo "Setting user to $USER_NAME in FreeDi.service"
sudo sed -i "s/{{USER}}/$USER_NAME/g" /etc/systemd/system/FreeDi.service

# Enable FreeDi.service to start at boot
echo "Enabling FreeDi.service to start at boot..."
sudo systemctl enable FreeDi.service
echo "FreeDi.service enabled to start at boot!"

###### Setup AutoFlasher service ######

# Installing the AutoFlasher.service
echo "Installing AutoFlasher.service..."
sudo cp /home/$USER_NAME/FreeDi/helpers/AutoFlasher.service /etc/systemd/system/AutoFlasher.service
echo "AutoFlasher.service installed!"

# Setting current user in AutoFlasher.service
echo "Setting user to $USER_NAME in AutoFlasher.service"
sudo sed -i "s/{{USER}}/$USER_NAME/g" /etc/systemd/system/AutoFlasher.service

# Enable AutoFlasher.service to start at boot
echo "Enabling AutoFlasher.service to start at boot..."
sudo systemctl enable AutoFlasher.service
echo "AutoFlasher.service enabled to start at boot!"

# Make hid-flash executable
echo "Making hid-flash executable..."
chmod +x /home/$USER_NAME/FreeDi/mainboard_and_toolhead_firmwares/hid-flash

echo "AutoFlasher.service installed!"

###### Reload systemd manager configuration ######

# Reload systemd manager configuration
echo "Reloading systemd manager configuration..."
sudo systemctl daemon-reload
echo "systemd manager configuration reloaded!"


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
