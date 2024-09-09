#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' install.sh

# Define variables
USER_NAME=$(whoami)
NM_CONF_FILE="/etc/NetworkManager/NetworkManager.conf"

# Set ownership and permissions for the ~/X3seriesLCD directory
echo "Setting ownership and permissions for ~/X3seriesLCD"
sudo chown -R $USER_NAME:$USER_NAME ~/X3seriesLCD
sudo chmod -R 755 ~/X3seriesLCD
echo "Ownership and permissions set"

# Console output
echo "Installing python3-pip git (necessary to run the program)..."
# Install python3-pip and git
sudo apt-get install -y python3-pip git
echo "python3-pip git install done!"

# Console output
echo "Installing pyserial (necessary for communication to the display)..."
# Install pyserial
sudo apt install python3-serial
echo "pyserial install done!"

# Console output
echo "Installing python3-requests (necessary for communication with moonraker)..."
# Install python3-requests
sudo apt-get install -y python3-requests
echo "python3-requests install done!"

# # Console output
# echo "Installing Pillow (necessary to create thumbnail)..."
# # Install Pillow
# sudo apt install python3-pil
# echo "Pillow install done!"

# Console output
echo "Setup dtbo for serial communication..."
# Install dtbo file for serial communication
sudo cp dtbo/rockchip-mkspi-uart1.dtbo /boot/dtb/rockchip/overlay/
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

echo "armbianEnv.txt customization comlpleted."

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
    sudo cp wifi/rtl8710bufw_SMIC.bin /lib/firmware/rtlwifi/
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
sudo chmod +x start.py
echo "start.py is now executable!"

# Make X3seriesLCD.service file executable
echo "Making X3seriesLCD.service executable..."
sudo chmod +x X3seriesLCD.service
echo "X3seriesLCD.service is now executable!"

# Move X3seriesLCD.service to systemd system directory
echo "Moving X3seriesLCD.service to /etc/systemd/system/"
sudo cp X3seriesLCD.service /etc/systemd/system/X3seriesLCD.service
echo "X3seriesLCD.service moved to /etc/systemd/system/"

# Set correct permissions for X3seriesLCD.service
echo "Setting permissions for /etc/systemd/system/X3seriesLCD.service"
sudo chmod 644 /etc/systemd/system/X3seriesLCD.service
echo "Permissions set to 644 for /etc/systemd/system/X3seriesLCD.service!"

# Reload systemd manager configuration
echo "Reloading systemd manager configuration..."
sudo systemctl daemon-reload
echo "systemd manager configuration reloaded!"

# Enable X3seriesLCD.service to start at boot
echo "Enabling X3seriesLCD.service to start at boot..."
sudo systemctl enable X3seriesLCD.service
echo "X3seriesLCD.service enabled to start at boot!"


# Update package lists
echo "Updating package lists..."
sudo apt update -y

# Install required packages
echo "Installing required packages for input shaping..."
sudo apt install -y python3-numpy python3-matplotlib libatlas-base-dev libopenblas-dev

# Install numpy using pip within the virtual environment
echo "Installing numpy in the virtual environment..."
~/klippy-env/bin/pip install -v numpy


# Console output
echo "Setup complete!"
echo "Please restart your system for the changes to take effect."
