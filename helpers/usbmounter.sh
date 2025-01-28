#!/bin/bash

USER="$1"
TARGET_DIR="/home/$USER/printer_data/gcodes"
ARG="$2"
ACTION=$(echo "$ARG" | cut -d'-' -f1)
DEVICE=$(echo "$ARG" | cut -d'-' -f2)

case "$ACTION" in
    add)
        for i in {1..10}; do
            MOUNT_POINT="$TARGET_DIR/usb$i"
            if ! mountpoint -q "$MOUNT_POINT"; then
                mkdir -p "$MOUNT_POINT"
                mount -o rw,umask=000 "/dev/$DEVICE" "$MOUNT_POINT"
                if [ $? -eq 0 ]; then
                    break
                else
                    rmdir "$MOUNT_POINT"
                    exit 1
                fi
            fi
        done
        ;;

    remove)
        MOUNT_POINT=$(mount | grep "/dev/$DEVICE" | awk '{print $3}')
        if [ -n "$MOUNT_POINT" ]; then
            umount "/dev/$DEVICE"
            if [ $? -eq 0 ]; then
                rmdir "$MOUNT_POINT"
            fi
        fi
        ;;

    *)
        exit 1
        ;;
esac