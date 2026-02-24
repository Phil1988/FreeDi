#!/bin/bash

# to delete '\r' signs use
# sed -i 's/\r$//' freedi_update.sh
# Set variables

echo "Starting the FreeDi update process..."

SERVICE="FreeDi.service"

# ── Directory layout ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$( cd -- "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd -P )"  # /home/<user>/FreeDi/FreeDiLCD
FREEDI_DIR="$( dirname "${SCRIPT_DIR}" )"                                        # /home/<user>/FreeDi
USER_HOME_DIR="$( dirname "${FREEDI_DIR}" )"                                     # /home/<user>
USER_NAME="$( basename "${USER_HOME_DIR}" )"                                          # The last path component is the user name -> <user>
USER_GROUP="$( id -gn "${USER_NAME}" )"                                               # The group name of the user


FREEDI_LCD_DIR="${FREEDI_DIR}/FreeDiLCD"
REPO_MODULE_DIR="${FREEDI_DIR}/klipper_module"
LCD_FIRMWARE_DIR="${FREEDI_DIR}/screen_firmwares"

KLIPPER_DIR="${USER_HOME_DIR}/klipper"
KLIPPER_EXTRAS_DIR="${KLIPPER_DIR}/klippy/extras"

# Set python path to klipper env
KLIPPER_ENV="${USER_HOME_DIR}/klippy-env"                                               # klipper virtual environment
KLIPPER_VENV_PYTHON_BIN="$KLIPPER_ENV/bin/python"                                       # klipper python binary


# -------- FreeDi repository ( $FREEDI_DIR ) ---------------------------
PULLABLE_FILES_FREEDI=(
    # example: "FreeDiLCD/always_pull_from_remote.py"
    "FreeDiLCD/freedi_update.sh"
)

BLOCKED_FILES_FREEDI=(
    # example: "FreeDiLCD/never_pull_from_remote.py"
)

# -------- Klipper repository ( $KLIPPER_DIR ) ------------------------------
# Basically files that doesnt exist in upstream klipper (thus not in $KLIPPER_EXTRAS_DIR)
PULLABLE_FILES_KLIPPER=(
    # example: "klippy/extras/freedi_custom_modified_file.py"
    "klippy/extras/freedi.py"
    "klippy/extras/auto_z_offset.py"
    "klippy/extras/freedi_hall_filament_width_sensor.py"
)

BLOCKED_FILES_KLIPPER=(
    # example: "klippy/extras/freedi_custom_modified_file.py"
    #"klippy/extras/hall_filament_width_sensor.py"

    # test showed this error/issue when trying to update klipper:
    # Updating 08a1c9f12..61c0c8d2e
    # From https://github.com/Klipper3d/klipper
    # * branch 61c0c8d2ef40340781835dd53fb04cc7a454e37a -> FETCH_HEAD
    # error: Your local changes to the following files would be overwritten by merge:
    # klippy/extras/hall_filament_width_sensor.py
    # Please commit your changes or stash them before you merge.
)



# ----- colour definitions -----
YLW='\033[1;33m'   # bold yellow
RED='\033[1;31m'   # bold red
RST='\033[0m'      # reset




############ legacyFreeDi 1.XX -> 2.00 Update ############

PRINTER_DATA_DIR="${USER_HOME_DIR}/printer_data"
PRINTER_CONFIG_DIR="${PRINTER_DATA_DIR}/config"
PRINTER_CFG="${PRINTER_CONFIG_DIR}/printer.cfg"
FREEDI_CFG_SRC="${FREEDI_DIR}/config_section/generic/freedi.cfg"
FREEDI_CFG_DST="${PRINTER_CONFIG_DIR}/freedi.cfg"



### Make sure the repo is complete
# 1) Detect and fix a partial clone ( --filter=blob:none )
if [ "$(git config --get remote.origin.partialclonefilter)" = "blob:none" ]; then
    echo "Partial clone detected – fetching all blobs ..."
    # switch the repo to a normal clone
    git config --unset-all remote.origin.partialclonefilter
    git config --unset-all remote.origin.promisor
    # fetch (download) everything that is still missing
    git fetch --no-filter --prune --tags --progress
fi

# 2) Detect and disable sparse-checkout
if git config --bool core.sparseCheckout | grep -q true; then
    echo "Sparse-checkout is active – disabling ..."
    git sparse-checkout disable
fi


### Installing and update the new introduced freedi.cfg
# 1. Copy freedi.cfg into the Klipper config directory
if install -m 644 -T "${FREEDI_CFG_SRC}" "${FREEDI_CFG_DST}"; then
    # Ensure proper ownership in case the script is executed as root
    chown "${USER_NAME}:${USER_GROUP}" "${FREEDI_CFG_DST}"
    echo "freedi.cfg copied and ownership set to ${USER_NAME}:${USER_GROUP}."
else
    echo "Error: failed to copy freedi.cfg." >&2
fi

# 2. Comment out the legacy [freedi] section in printer.cfg
if grep -q '^\[freedi\]$' "${PRINTER_CFG}"; then
    sed -i '
        /^\[freedi\]$/,/^\[/{         # range: from [freedi] up to next "[" line
            /^\[freedi\]$/  s/^/#/    # comment the [freedi] header
            /^\[/          b          # if line starts with [, skip further cmds
            s/^/#/                     # otherwise: comment the line
        }
    ' "${PRINTER_CFG}"

    echo "Legacy [freedi] section commented out."
fi

# 3. Insert include statement where the former [freedi] section started
if ! grep -q "^\[include freedi.cfg\]" "${PRINTER_CFG}"; then
    # Find the line number of the (now commented) [freedi] header
    FREEDI_LINE=$(grep -n -m1 '^[#]*\[freedi\]' "${PRINTER_CFG}" | cut -d':' -f1)
    if [[ -n "${FREEDI_LINE}" ]]; then
        # Insert the include line directly above that header
        sed -i "${FREEDI_LINE}i [include freedi.cfg]\n" "${PRINTER_CFG}"
        echo "Include statement inserted near the original [freedi] section."
    else
        echo "Warning: could not locate the commented [freedi] section; include line not added." >&2
    fi
else
    echo "Include statement already present in printer.cfg."
fi



# Activate the Klipper virtual environment and install required Python packages
echo "Activating Klipper virtual environment and installing Python packages..."

if [ ! -d "$KLIPPER_ENV" ]; then
	echo "Klippy env doesn't exist so I can't continue installation..."
	exit 1
fi

PYTHON_V=$($KLIPPER_VENV_PYTHON_BIN -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "Klipper environment python version: $PYTHON_V"

# Arrange Python requirements from requirements.txt
echo "Arranging Python requirements..."
"${KLIPPER_ENV}/bin/pip" install --upgrade pip 
"${KLIPPER_ENV}/bin/pip" install -r "${FREEDI_DIR}/requirements.txt"
if [ $? -ne 0 ]; then
    echo "Failed to install Python requirements."
    exit 1
fi
echo "Python requirements installed from requirements.txt."



###### Installing klipper modules ######

# Create a symbolic links for needed modules to the Klipper extras directory
FREEDI_MODULES=(
    "freedi.py"
    "qidi_auto_z_offset/auto_z_offset.py"
    #"reverse_homing.py"
    #"hall_filament_width_sensor.py"
    "freedi_hall_filament_width_sensor.py"
)

for MODULE_PATH in "${FREEDI_MODULES[@]}"; do
    MODULE_NAME=$(basename "${MODULE_PATH}")

    echo "Creating a symbolic link for ${MODULE_NAME} from ${REPO_MODULE_DIR}/${MODULE_PATH} to ${KLIPPER_EXTRAS_DIR} …"
    if ln -sf "${REPO_MODULE_DIR}/${MODULE_PATH}" "${KLIPPER_EXTRAS_DIR}/${MODULE_NAME}"; then
        # Ensure the symlink belongs to the regular user, not root
        chown -h "${USER_NAME}:${USER_GROUP}" "${KLIPPER_EXTRAS_DIR}/${MODULE_NAME}"
        echo "Successfully installed ${MODULE_NAME} to ${KLIPPER_EXTRAS_DIR}."
    else
        echo "Error: failed to create a symbolic link for ${MODULE_NAME}." >&2
        exit 1
    fi
done


############ Git housekeeping to prevent dirty repos and setting the correct logic (updateable or not) ############




# Check if the script is run inside a Git repository
if [ ! -d "${FREEDI_DIR}/.git" ]; then
    echo "Error: Not a git repository. Please initialize the repository first."
fi

# Ensure if the Klipper extras directory exists
if [ ! -d "$KLIPPER_EXTRAS_DIR" ]; then
    echo "Error: Klipper extras directory not found at $KLIPPER_EXTRAS_DIR."
    echo "Make sure Klipper is installed correctly."
fi


# Wrapper to execute commands as the target user when running as root
# Especially useful for Git operations
run_as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$USER_NAME" -- "$@"
    else
        "$@"
    fi
}

# Helper: keep repo clean for a given list of files
# • pullable → assume-unchanged
# • blocked  → skip-worktree
# • detects & clears an already recorded change (typechange, content, …)
# • runs Git as $USER_NAME even when script is executed as root
clean_repo() {
    local repo="$1"
    local mode="$2"
    shift 2
    local files=("$@")

    # Determine the .git directory and build absolute path to info/exclude
    local git_dir
    git_dir="$(run_as_user git -C "$repo" rev-parse --git-dir)"
    # <-- changed: use absolute path for exclude file
    local exclude_file="${repo}/${git_dir}/info/exclude"
    echo "Exclude file resolved to: $exclude_file"

    # Ensure the exclude file exists
    run_as_user mkdir -p "$(dirname "$exclude_file")"
    run_as_user touch "$exclude_file"

    for f in "${files[@]}"; do
        local full_path="${repo}/${f}"
        local st
        st="$(run_as_user git -C "$repo" status --porcelain -- "$f")"

        # Warn if file/symlink is missing in working tree
        if [ ! -e "$full_path" ]; then
            echo -e "${YLW}Notice: ${f} does not exist in working tree – index/ignore rules are still applied.${RST}"
        fi

        # ------------------------------------------------------------------
        # CASE 1 : tracked file or type-change
        # ------------------------------------------------------------------
        if run_as_user git -C "$repo" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
           || [[ $st =~ ^.?T ]]; then

            # Check if this file has changes already
            local dirty_pre=false
            if [ -n "$st" ]; then
                echo -e "${YLW}Detected changes for ${f} in index / working tree (causes dirty repo).${RST}"
                dirty_pre=true
            fi

            if [[ "$mode" == "pullable" ]]; then
                if run_as_user git -C "$repo" update-index --assume-unchanged -- "$f"; then
                    echo -e "Git will now ignore local changes to ${f} (assume-unchanged)."
                else
                    echo -e "${RED}Warning: git update-index failed for ${f} – file NOT marked.${RST}"
                fi
            else
                if run_as_user git -C "$repo" update-index --skip-worktree -- "$f"; then
                    echo -e "Git will keep your local version of ${f} (skip-worktree)."
                else
                    echo -e "${RED}Warning: git update-index failed for ${f} – file NOT marked.${RST}"
                fi
            fi

            # If it was dirty, refresh index to clear existing change
            if [ "$dirty_pre" = true ]; then
                echo -e "${YLW}Cleaning index / working tree for ${f}...${RST}"
                run_as_user git -C "$repo" update-index --really-refresh -q -- "$f"
                if run_as_user git -C "$repo" status --porcelain -- "$f" | grep -q .; then
                    echo -e "${RED}Index still reports changes for ${f}!${RST}"
                else
                    echo -e "${YLW}Index cleaned for ${f}.${RST}"
                fi
            fi

        # ------------------------------------------------------------------
        # CASE 2 : untracked file → add to info/exclude
        # ------------------------------------------------------------------
        else
            if ! grep -Fxq "$f" "$exclude_file"; then
                if printf '%s\n' "$f" | run_as_user tee -a "$exclude_file" >/dev/null; then
                    echo -e "Added ${f} to $(basename "$exclude_file") (untracked→exclude)."
                else
                    echo -e "${RED}Warning: failed to write ${f} to $(basename "$exclude_file").${RST}"
                fi
            else
                echo -e "${f} already listed in $(basename "$exclude_file") – skipping."
            fi
        fi
    done
}




# Run git cleaning - Apply the definitions above
clean_repo "$FREEDI_DIR" pullable "${PULLABLE_FILES_FREEDI[@]}"
clean_repo "$FREEDI_DIR" blocked  "${BLOCKED_FILES_FREEDI[@]}"

clean_repo "$KLIPPER_DIR"     pullable "${PULLABLE_FILES_KLIPPER[@]}"
clean_repo "$KLIPPER_DIR"     blocked  "${BLOCKED_FILES_KLIPPER[@]}"




############ Update finished: Restart klipper and FreeDi.service ############

# Restart Klipper to load the new modules
echo "Restarting Klipper service..."
sudo systemctl restart klipper
