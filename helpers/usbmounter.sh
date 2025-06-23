#!/bin/bash

USER="$1"
TARGET_DIR="/home/$USER/printer_data/gcodes"
ARG="$2"
ACTION=$(echo "$ARG" | cut -d'-' -f1)
DEVICE=$(echo "$ARG" | cut -d'-' -f2)

# Define the vendor and product IDs to ignore
IGNORED_VENDOR_ID="a69c"
IGNORED_PRODUCT_ID="5721"

# Extract vendor and product ID from the device information
DEVICE_VENDOR_ID=$(lsusb | grep "$DEVICE" | awk '{print $6}' | cut -d':' -f1)
DEVICE_PRODUCT_ID=$(lsusb | grep "$DEVICE" | awk '{print $6}' | cut -d':' -f2)

# Check if the device should be ignored
if [[ "$DEVICE_VENDOR_ID" == "$IGNORED_VENDOR_ID" && "$DEVICE_PRODUCT_ID" == "$IGNORED_PRODUCT_ID" ]]; then
    echo "Ignoring device $DEVICE with vendor ID $DEVICE_VENDOR_ID and product ID $DEVICE_PRODUCT_ID"
    echo "It's an AIC8800DC in mass storage mode, switching to wifi mode"
    exit 0
fi

echo "Script started: ACTION=$ACTION, DEVICE=$DEVICE"

PART_NUM=$(echo "$DEVICE" | grep -o '[0-9]*$')

# Apply a delay if partition number > 1
if [ "$ACTION" = "add" ] && [ "$PART_NUM" -gt 1 ]; then
    DELAY=$(echo "scale=1; ($PART_NUM - 1) * 0.2" | bc)
    echo "Detected partition number $PART_NUM, sleeping for $DELAY seconds to prevent wrong detection."
    sleep "$DELAY"
fi

case "$ACTION" in
    add)
        echo "Attempting to mount /dev/$DEVICE"
        for i in {1..10}; do
            MOUNT_POINT="$TARGET_DIR/usb$i"
            if ! mountpoint -q "$MOUNT_POINT"; then
                echo "Using mount point: $MOUNT_POINT"
                mkdir -p "$MOUNT_POINT"

                # Check if the label is "RPI-RP2"
                LABEL=$(/sbin/blkid -o value -s LABEL "/dev/$DEVICE" 2>/dev/null)
                if [ "$LABEL" = "RPI-RP2" ]; then
                    echo "Device /dev/$DEVICE has label RPI-RP2, not mounting."
                    exit 0
                fi

                FSTYPE=$(/sbin/blkid -o value -s TYPE "/dev/$DEVICE" 2>&1)
                echo "Filesystem detected: $FSTYPE"

                case "$FSTYPE" in
                    vfat)
                        echo "Mounting FAT32 (vfat)"
                        mount -t vfat -o rw,umask=000 "/dev/$DEVICE" "$MOUNT_POINT" 2>&1 || echo "ERROR: Mount failed" >&2
                        ;;
                    ntfs)
                        echo "Mounting NTFS"
                        mount -t ntfs-3g -o rw,umask=000 "/dev/$DEVICE" "$MOUNT_POINT" 2>&1 || echo "ERROR: Mount failed" >&2
                        ;;
                    ext4)
                        echo "Mounting EXT4"
                        mount -t ext4 -o rw "/dev/$DEVICE" "$MOUNT_POINT" 2>&1 || echo "ERROR: Mount failed" >&2
                        ;;
                    *)
                        echo "ERROR: Unsupported filesystem: $FSTYPE" >&2
                        rmdir "$MOUNT_POINT"
                        exit 1
                        ;;
                esac

                if mount | grep -q "$MOUNT_POINT"; then
                    echo "Mount successful: $MOUNT_POINT"
                    break
                else
                    echo "ERROR: Mounting failed for /dev/$DEVICE" >&2
                    rmdir "$MOUNT_POINT"
                    exit 1
                fi
            fi
        done
        ;;

    remove)
        echo "Attempting to unmount /dev/$DEVICE"
        MOUNT_POINT=$(mount | grep "/dev/$DEVICE" | awk '{print $3}')
        if [ -n "$MOUNT_POINT" ]; then
            echo "Unmounting from $MOUNT_POINT"
            umount "/dev/$DEVICE" 2>&1 || echo "ERROR: Unmount failed" >&2
            if [ $? -eq 0 ]; then
                echo "Unmount successful"
                rmdir "$MOUNT_POINT"
            fi
        else
            echo "ERROR: No mount point found for /dev/$DEVICE" >&2
        fi
        ;;

    *)
        echo "ERROR: Unknown action: $ACTION" >&2
        exit 1
        ;;
esac