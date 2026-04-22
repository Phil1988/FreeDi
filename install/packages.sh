#!/bin/bash
# Installs all required apt packages for FreeDi.
# Sourced by install.sh — expects IS_FREEDI_IMAGE, OS_CODENAME, RED, GRN, RST to be set.

################################################################################
# INSTALL APT PACKAGES
################################################################################

echo "Updating apt package lists..."
sudo apt-get update || { echo "${RED}Failed to update apt package lists.${RST}"; exit 1; }

# for flashing the toolhead katapult firmware using flashtool.py
echo "Checking if python3-serial package is already installed..."
if dpkg -l | grep -q python3-serial; then
    echo "python3-serial package is already installed. Skipping installation."
else
    echo "python3-serial package is not installed. Installing now..."
    sudo apt-get install -y python3-serial
    if [ $? -eq 0 ]; then
        echo "python3-serial package installed successfully!"
    else
        echo "${RED}Failed to install python3-serial package.${RST}"
        exit 1
    fi
fi

# for flashing the Plus4 toolhead klipper firmware
echo "Checking if stlink-tools package is already installed..."
if dpkg -l | grep -q stlink-tools; then
    echo "stlink-tools package is already installed. Skipping installation."
else
    echo "stlink-tools package is not installed. Installing now..."
    sudo apt-get install -y stlink-tools
    if [ $? -eq 0 ]; then
        echo "stlink-tools package installed successfully!"
    else
        echo "${RED}Failed to install stlink-tools package.${RST}"
        exit 1
    fi
fi

# Input shaping dependencies (skip on FreeDi image — already included)
echo "Installing required packages for input shaping..."
if [[ "$OS_CODENAME" == "trixie" ]]; then
    # Debian 13+: libatlas3-base replaces libatlas-base-dev
    sudo apt-get install -y libatlas3-base libopenblas-dev ntfs-3g
else
    sudo apt-get install -y libatlas-base-dev libopenblas-dev ntfs-3g
fi
if [ $? -ne 0 ]; then
    echo "${RED}Error: Failed to install input shaping dependencies.${RST}"
    exit 1
fi
echo "Input shaping dependencies installed successfully."