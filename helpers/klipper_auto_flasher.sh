#!/bin/bash

##   muss ausführbar gemacht werden mit
##   chmod +x /home/mks/FreeDi/mainboard_and_toolhead_firmwares/hid-flash


# Get the absolute path of the script
script_dir="$(cd "$(dirname "$0")" && pwd)"

# Define the absolute paths to the firmware files
toolhead_firmware_path="$script_dir/../mainboard_and_toolhead_firmwares/v0.12.0-289/Toolhead_RP2040.uf2"
hid_flash_path="$script_dir/../mainboard_and_toolhead_firmwares/hid-flash"
mcu_firmware="$script_dir/../mainboard_and_toolhead_firmwares/v0.12.0-289/X_4.bin"
serial_port="ttyS0"

# Find matching /dev/sd*[0-9] to see if toolhead is in boot mode
for device in /dev/sd*[0-9]; do
    # Check if the device exists
    if [ -e "$device" ]; then
        # Get the size of the partition
        size=$(lsblk | grep "$(basename "$device")" | awk '{print $4}')

        # Check if the size matches exactly 128M
        if [ "$size" == "128M" ]; then
            echo "Device $device size is exactly 128M"
            
            # Copy (flash) the toolhead klipper firmware to the device
            echo "Copying firmware to $device..."
            sudo cp "$toolhead_firmware_path" "$device"

            # Check if the copy was successful
            if [ $? -eq 0 ]; then
                echo "Firmware successfully copied to $device"

                sudo service klipper stop;
                sudo service klipper start;

                # Wait for Klipper service runtime to stabilize (with timeout)
                max_attempts=30  # Timeout after 30 seconds
                attempt=0

                while true; do
                    runtime=$(systemctl show klipper.service --property=ActiveEnterTimestampMonotonic | awk -F'=' '{print $2}')
                    if [ -n "$runtime" ] && [ "$runtime" -ge 5000000 ]; then
                        echo "Klipper service has been running for at least 5 seconds."
                        break
                    fi

                    # Increment attempt counter and check for timeout
                    attempt=$((attempt + 1))
                    if [ "$attempt" -ge "$max_attempts" ]; then
                        echo "Timeout waiting for Klipper service to stabilize."
                        exit 1
                    fi

                    sleep 1
                done


                sleep 10
                echo "FIRMWARE_RESTART" | sudo tee /home/mks/printer_data/comms/klippy.serial
                sudo service klipper stop &

                # Flash the MCU firmware
                $hid_flash_path "$mcu_firmware" "$serial_port"

                # Starting klipper again
                echo "Starting Klipper service..."
                sleep 3
                if ! sudo service klipper start; then
                    echo "Failed to start Klipper service."
                    exit 1
                fi


            else
                echo "Failed to copy firmware to $device"
            fi
        else
            echo "Device $device size is $size (not 128M)"
        fi
    else
        echo "Device $device not found"
    fi

done
