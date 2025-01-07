import os
import sys
import psutil
from main import main as main_function  # Import the main function from main.py


def is_instance_running(script_name):
    """Check if another instance of the script is running."""
    current_pid = os.getpid()
    script_name = os.path.abspath(script_name)  # Ensure absolute path for comparison

    matching_processes = []

    for proc in psutil.process_iter(['pid', 'cmdline']):
        try:
            cmdline = proc.info['cmdline']
            if cmdline:
                # Check if the script name matches and it's not the current process
                if proc.info['pid'] != current_pid and script_name in cmdline:
                    matching_processes.append(proc.info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    return len(matching_processes) > 0

if __name__ == "__main__":
    # Ensure the script name matches explicitly
    script_name = os.path.abspath(__file__)
    if is_instance_running(script_name):
        print(f"Another instance of {script_name} is already running.")
        sys.exit(1)

    main_function()  # Call the main function from main.py
