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

# 4) Realtek RTL8811AU/RTL8821AU (e.g. TP-Link Archer T2U Nano, T600U Nano)
RTL8821AU_IDS="0bda:a811|0bda:0811|0bda:0820|0bda:0821|0bda:0823|2357:011e|2357:011f|2357:0120"
device_info_rtl8821au=$(lsusb | grep -iE "$RTL8821AU_IDS")

# 5) Realtek multi-mode dongles in "driver CD" mode (Windows driver CD-ROM)
REALTEK_CD_IDS="0bda:1a2b|0bda:a192"
device_info_realtek_cd=$(lsusb | grep -iE "$REALTEK_CD_IDS")

RTL8821AU_DRIVER_REPO="https://github.com/morrownr/8821au-20210708.git"
ARMBIAN_ENV_FILE="${ARMBIAN_ENV_FILE:-/boot/armbianEnv.txt}"

# Kernel >= 6.13 ships rtw88_8821au; older kernels (e.g. 6.6) need the out-of-tree driver
setup_rtl8821au_driver() {
    if modinfo rtw88_8821au >/dev/null 2>&1; then
        echo "Kernel driver rtw88_8821au is available."
        if [ ! -f /lib/firmware/rtw88/rtw8821a_fw.bin ]; then
            printf "%b\n" "${RED}Warning: firmware /lib/firmware/rtw88/rtw8821a_fw.bin is missing (install linux-firmware/armbian-firmware).${RST}"
        fi
    elif modinfo 8821au >/dev/null 2>&1; then
        echo "8821au driver is already installed – skipping."
    elif [ ! -d "/lib/modules/$(uname -r)/build" ]; then
        printf "%b\n" "${RED}Warning: kernel headers for $(uname -r) not found, cannot build the 8821au driver.${RST}"
    else
        echo "Building the 8821au DKMS driver (this can take 15 minutes or more)..."
        local build_dir
        build_dir=$(mktemp -d)
        if sudo apt-get install -y dkms git build-essential bc &&
            git clone --depth 1 "$RTL8821AU_DRIVER_REPO" "$build_dir/8821au" &&
            (cd "$build_dir/8821au" && sudo ./install-driver.sh NoPrompt); then
            echo "8821au driver installed."
        else
            printf "%b\n" "${RED}Warning: building the 8821au driver failed. Wi-Fi will not work with this dongle; use Ethernet or see ${RTL8821AU_DRIVER_REPO}${RST}"
        fi
        rm -rf "$build_dir"
    fi
}

# usb-storage grabs the driver CD before usb_modeswitch can switch it (fixed in the kernel
# in 2025 with the same quirk). Tell usb-storage to ignore these IDs on older kernels.
add_realtek_cd_quirks() {
    local quirk
    for quirk in 0x0bda:0x1a2b:i 0x0bda:0xa192:i; do
        if grep -q "^usbstoragequirks=.*${quirk}" "$ARMBIAN_ENV_FILE"; then
            continue
        elif grep -q "^usbstoragequirks=." "$ARMBIAN_ENV_FILE"; then
            sudo sed -i "s/^usbstoragequirks=.*/&,${quirk}/" "$ARMBIAN_ENV_FILE"
        elif grep -q "^usbstoragequirks=" "$ARMBIAN_ENV_FILE"; then
            sudo sed -i "s/^usbstoragequirks=.*/usbstoragequirks=${quirk}/" "$ARMBIAN_ENV_FILE"
        else
            echo "usbstoragequirks=${quirk}" | sudo tee -a "$ARMBIAN_ENV_FILE" > /dev/null
        fi
    done
}

# Realtek RTL8811AU/RTL8821AU in Wi-Fi mode  ---------------------------
if [ -n "$device_info_rtl8821au" ]; then
    echo "Realtek RTL8811AU/RTL8821AU detected: $(echo "$device_info_rtl8821au" | awk '{print $6}')"
    add_realtek_cd_quirks
    setup_rtl8821au_driver
    echo "WiFi setup for RTL8811AU/RTL8821AU finished."

# RTL8188GU  --------------------------------------------------------
# lsusb names the shared Realtek driver CD id 0bda:1a2b "RTL8188GU", so this branch also
# catches other Realtek dongles (e.g. RTL8811AU) that are still in driver CD mode.
elif [ -n "$device_info_rtl" ]; then
    echo "RTL8188GU detected."
    vendor_id=$(echo "$device_info_rtl" | awk '{print $6}' | cut -d: -f1)
    product_id=$(echo "$device_info_rtl" | awk '{print $6}' | cut -d: -f2)
    echo "vendor_id: $vendor_id, product_id: $product_id"

    # Switch device into WLAN mode
    sudo usb_modeswitch -v "$vendor_id" -p "$product_id" -J

    # A dongle in driver CD mode may turn out to be an RTL8811AU/RTL8821AU after switching
    if echo "$device_info_rtl" | grep -qiE "$REALTEK_CD_IDS"; then
        add_realtek_cd_quirks
        sleep 5
        if lsusb | grep -qiE "$REALTEK_CD_IDS"; then
            # still in CD mode: try the standard eject used by usb-modeswitch-data
            sudo usb_modeswitch -K -v "$vendor_id" -p "$product_id"
            sleep 5
        fi
        device_info_rtl8821au=$(lsusb | grep -iE "$RTL8821AU_IDS")
    fi

    if [ -n "$device_info_rtl8821au" ]; then
        echo "Switched to Wi-Fi mode: $(echo "$device_info_rtl8821au" | awk '{print $6}') (RTL8811AU/RTL8821AU)"
        setup_rtl8821au_driver
        echo "WiFi setup for RTL8811AU/RTL8821AU finished."
    # Copy firmware only if it is not already present
    elif [ -f "$TARGET_FW" ]; then
        echo "Firmware already present – skipping copy."
        echo "WiFi setup for RTL8188GU finished."
    else
        if [ ! -f "${WIFI_DIR}/rtl8710bufw_SMIC.bin" ]; then
            echo "${RED}Error: firmware file ${WIFI_DIR}/rtl8710bufw_SMIC.bin not found.${RST}"
            exit 1
        fi
        sudo cp "${WIFI_DIR}/rtl8710bufw_SMIC.bin" "$TARGET_FW" || {
            echo "${RED}Error: failed to copy firmware.${RST}"; exit 1; }
        echo "WiFi setup for RTL8188GU finished."
    fi

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
