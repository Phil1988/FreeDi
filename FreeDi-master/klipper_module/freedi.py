# FreeDi Module for Klipper
# This module registers a custom [FreeDi] section in the printer.cfg file
# and loads the associated parameters.

import logging

class FreeDi:
    def __init__(self, config):
        # Read parameters from the configuration file
        self.printer_model = config.get('printer_model', 'unknown')
        self.baudrate = config.get('baudrate', 115200)
        self.serial_port = config.get('serial_port', '/dev/ttyS1')
        self.url = config.get('url', '127.0.0.1')
        self.moonraker_port = config.get('moonraker_port', '7125')
        self.webUI_port = config.get('webUI_port', '80')
        self.api_key = config.get('api_key', 'XXXXXX')
        self.klippy_socket = config.get('klippy_socket', '/home/mks/printer_data/comms/klippy.sock')
        self.channel = config.get('channel', 'stable')
        self.wizard = config.get('wizard', 'True')
        self.preset1_name = config.get('preset1_name', 'PLA')
        self.preset2_name = config.get('preset2_name', 'ASA')
        self.preset3_name = config.get('preset3_name', 'PETG')
        self.preset4_name = config.get('preset4_name', 'TPU')
        self.default_temp_extruder = config.get('default_temp_extruder', '220')
        self.default_temp_bed = config.get('default_temp_bed', '60')
        self.default_temp_chamber = config.get('default_temp_chamber', '45')
        self.default_speed_partfan = config.get('default_speed_partfan', '100')
        self.default_speed_sidefan = config.get('default_speed_sidefan', '100')
        self.default_speed_filterfan = config.get('default_speed_filterfan', '100')
        self.sync_case_light_with_display = config.get('sync_case_light_with_display', 'True')
        self.default_brightness = config.get('default_brightness', '100')
        self.lcd_dim_time = config.get('lcd_dim_time', '10')    
        self.lcd_dim_brightness = config.get('lcd_dim_brightness', '15')
        self.lcd_sleep_time = config.get('lcd_sleep_time', '20')
        self.install_klipper_module = config.get('install_klipper_module', 'False')
        self.flash_MCU = config.get('flash_MCU', 'False')
        self.flash_toolhead = config.get('flash_toolhead', 'False')
        self.flash_display = config.get('flash_display', 'False')

        # Default extrusion lengths for the Extruder menu (in millimeters)
        self.extruder_length_1 = config.get('extruder_length_1', '10.0')
        self.extruder_length_2 = config.get('extruder_length_2', '20.0')
        self.extruder_length_3 = config.get('extruder_length_3', '50.0')
        
        # Default move and extrude step lengths for Move and Move&Extrude menus (in millimeters)
        self.move_extrude_length_1 = config.get('move_extrude_length_1', '0.1')
        self.move_extrude_length_2 = config.get('move_extrude_length_2', '1.0')
        self.move_extrude_length_3 = config.get('move_extrude_length_3', '10.0')
        self.move_extrude_length_4 = config.get('move_extrude_length_4', '50.0')
        self.move_extrude_length_5 = config.get('move_extrude_length_5', '100.0')
        
        # Enable visual feedback on touch events
        self.touch_acoustic_feedback = config.get('touch_acoustic_feedback', 'True')


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

