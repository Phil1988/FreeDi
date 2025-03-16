#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' install.sh

# Set variables
BKDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

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


###### Deleting old X3seriesLCD ######

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
sudo rm -rf $BKDIR/X3seriesLCD
echo "X3seriesLCD directory removed!"
