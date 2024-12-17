#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' install.sh

# Path to the config.ini file
config_file="config.ini"

# Read the printer model from the config file
printer_model=$(grep -oP '^printer_model\s*=\s*\K.+' "$config_file")

# Check if the value was read successfully
if [ -n "$printer_model" ]; then
    echo "The printer model is: $printer_model"
else
    echo "Error: Printer model not found."
fi

#Set variables
SERVICE="FreeDiLCD.service"
BKDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
X3DIR="${BKDIR}/FreeDiLCD"
LCDFIRMWAREDIR="${BKDIR}/screen_firmwares"

# Set python path to klipper env
KENV="${HOME}/klippy-env"
PYTHON_EXEC="$KENV/bin/python"


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

# Find the lcd_helper shared object file
lcd_helper_file=$(find "${X3DIR}" -name "lcd_helper*.so" | head -n 1)

# Check if the file was found
if [ -z "$lcd_helper_file" ]; then
    echo "lcd_helper shared object file not found in ${X3DIR}."
    exit 1
fi

#echo "Found lcd_helper file: $lcd_helper_file"

# Run the shared object with the given arguments
$PYTHON_EXEC -c "import sys; sys.path.insert(0, '${X3DIR}'); import lcd_helper; lcd_helper.run('${LCD_FIRMWARE}', '${LCD_SERIAL_PORT}', ${LCD_SERIAL_INIT_BAUD}, ${LCD_SERIAL_FLASH_BAUD})"


if [ $? -ne 0 ]; then
	echo "Error: Firmware update failed!"
	# You can handle the failure here (e.g., logging, retrying, etc.)
	exit 1
else
	echo "Firmware up to date"
fi

# Start FreeDiLCD.service
echo "Starting FreeDiLCD.service..."
systemctl start FreeDiLCD.service
echo "FreeDiLCD.service started!"

# Console output
echo "Update complete!"
echo "Please restart your system for the changes to take effect."
