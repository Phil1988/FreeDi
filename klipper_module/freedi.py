# FreeDi Module for Klipper
# This module registers a custom [FreeDi] section in the printer.cfg file
# and loads the associated parameters.

import logging

class FreeDi:
    def __init__(self, config):
        # Read parameters from the configuration file
        self.printer_model = config.get('printer_model', 'unknown')
        self.baudrate = config.getint('baudrate', 115200)
        self.serial_port = config.get('serial_port', '/dev/ttyS0')

        # Log the loaded parameters (for debugging purposes)
        self.log_info(f"FreeDi loaded: printer_model={self.printer_model}, "
                      f"baudrate={self.baudrate}, serial_port={self.serial_port}")

    def log_info(self, message):
        # Use Klipper's integrated logging system to output messages
        logging.info(message)


# Klipper initialization function
# This function is called when the [FreeDi] section is found in the printer.cfg
def load_config(config):
    return FreeDi(config)

