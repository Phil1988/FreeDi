import os
import sys
import subprocess

def run_and_delete_bash_script(file_name):
    if not os.path.exists(file_name):
        return
    
    try:
        result = subprocess.run(["bash", file_name], capture_output=True, text=True, check=True)
        print("Script Output:\n", result.stdout)
        os.remove(file_name)
        print(f"File '{file_name}' has been deleted.")
    except subprocess.CalledProcessError as e:
        print("Error occurred:\n", e.stderr)
    except FileNotFoundError:
        print(f"File '{file_name}' not found. Nothing to delete.")

# Run the update script
file_name = "freedi_update.sh"
run_and_delete_bash_script(file_name)

import psutil

# Import the main function from main.py
from main import main as main_function  

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
