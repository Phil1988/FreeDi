#!/bin/bash

################################################################################
# CONFIGURE WIFI
################################################################################

# Console output
echo "Installing WiFi..."

# Update package lists
# Dont. Takes much time.
#sudo apt-get update

# Install usb-modeswitch
sudo apt-get install -y usb-modeswitch || {
    echo "${RED}Failed to install usb-modeswitch.${RST}"
    exit 1
}

#install eject package for safely ejecting the AIC8800DC after flashing the firmware
sudo apt-get install -y eject || {
    echo "${RED}Failed to install eject.${RST}"
    exit 1
}


# ------------------------------------------------------------------
# Detect which USB Wi-Fi dongle is attached
# ------------------------------------------------------------------
echo "Detecting WiFi chip..."

# 1) Realtek RTL8188GU (needs firmware only)
device_info_rtl=$(lsusb | grep -i "RTL8188GU")
TARGET_FW="/lib/firmware/rtlwifi/rtl8710bufw_SMIC.bin"

# 2) AIC8800DC appears first as mass-storage (id 0x5721)
device_info_aic_mass_storage=$(lsusb | grep -i "a69c:5721")

# 3) AIC8800DC already switched to Wi-Fi mode (id 0x0013)
device_info_aic_wifi=$(lsusb | grep -i "2604:0013")

# Package/-deb file for AIC8800DC
AIC_PKG="aic8800-dkms"
AIC_DEB="${WIFI_DIR}/${AIC_PKG}.deb"

# RTL8188GU  --------------------------------------------------------
if [ -n "$device_info_rtl" ]; then
    echo "RTL8188GU detected."
    vendor_id=$(echo "$device_info_rtl" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_rtl" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Switch device into WLAN mode
    sudo usb_modeswitch -v "$vendor_id" -p "$product_id" -J

    # Copy firmware only if it is not already present
    if [ -f "$TARGET_FW" ]; then
        echo "Firmware already present – skipping copy."
    else
        if [ ! -f "${WIFI_DIR}/rtl8710bufw_SMIC.bin" ]; then
            echo "${RED}Error: firmware file ${WIFI_DIR}/rtl8710bufw_SMIC.bin not found.${RST}"
            exit 1
        fi
        sudo cp "${WIFI_DIR}/rtl8710bufw_SMIC.bin" "$TARGET_FW" || {
            echo "${RED}Error: failed to copy firmware.${RST}"; exit 1; }
    fi
    echo "WiFi setup for RTL8188GU finished."

# AIC8800DC shows up as mass-storage  -------------------------------
elif [ -n "$device_info_aic_mass_storage" ]; then
    echo "AIC8800DC detected as mass-storage device."
    vendor_id=$(echo "$device_info_aic_mass_storage" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_aic_mass_storage" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Switch device from storage to Wi-Fi mode
    sudo usb_modeswitch -KQ -v "$vendor_id" -p "$product_id"

    # Create udev rule so that future plug-ins are switched automatically
    echo "Creating udev rule for automatic mode-switch..."
    echo "ACTION==\"add\", ATTR{idVendor}==\"${vendor_id}\", ATTR{idProduct}==\"${product_id}\", RUN+=\"/usr/sbin/usb_modeswitch -v ${vendor_id} -p ${product_id} -KQ\"" \
        | sudo tee /etc/udev/rules.d/99-usb_modeswitch.rules >/dev/null

    # Reload udev rules immediately
    sudo udevadm control --reload-rules

    # Install driver only if it is NOT already present (skip on FreeDi image)
    if [ "$IS_FREEDI_IMAGE" = true ] || dpkg -s "$AIC_PKG" >/dev/null 2>&1; then
        if [ "$IS_FREEDI_IMAGE" = true ]; then
            echo "Running on FreeDi image; driver installation skipped."
        else
            echo "$AIC_PKG is already installed – skipping."
        fi
    else
        echo "Installing package $AIC_PKG..."
        if [ ! -f "$AIC_DEB" ]; then
            echo "${RED}Error: driver package $AIC_DEB not found.${RST}"
            exit 1
        fi
        sudo dpkg -i "$AIC_DEB" || { echo "${RED}Error: dpkg failed.${RST}"; exit 1; }
    fi
    echo "WiFi setup for AIC8800DC finished."

# AIC8800DC already in Wi-Fi mode  ---------------------------------
elif [ -n "$device_info_aic_wifi" ]; then
    echo "AIC8800DC detected in Wi-Fi mode."
    vendor_id=$(echo "$device_info_aic_wifi" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_aic_wifi" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Install driver only if it is NOT already present (skip on FreeDi image as drivers are already included there)
    if [ "$IS_FREEDI_IMAGE" = true ] || dpkg -s "$AIC_PKG" >/dev/null 2>&1; then
        if [ "$IS_FREEDI_IMAGE" = true ]; then
            echo "Running on FreeDi image; driver installation skipped."
        else
            echo "$AIC_PKG is already installed – skipping."
        fi
    else
        echo "Installing package $AIC_PKG..."
        if [ ! -f "$AIC_DEB" ]; then
            echo "${RED}Error: driver package $AIC_DEB not found.${RST}"
            exit 1
        fi
        sudo dpkg -i "$AIC_DEB" || { echo "${RED}Error: dpkg failed.${RST}"; exit 1; }
    fi
    echo "WiFi setup for AIC8800DC finished."

# No supported device found  ---------------------------------------
else
    echo "No supported WiFi chip detected. Please make sure the dongle is connected."
fi
