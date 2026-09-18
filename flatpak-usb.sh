#!/usr/bin/env bash

# USB Root Directory - dynamically detected based on script location
USB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OSTREE_REPO="${USB_DIR}/.ostree/repo"

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =========================================
# 1. AUTO-CHECK & INSTALL MISSING PACKAGES
# =========================================
check_dependencies() {
    if command -v sudo &> /dev/null; then
        echo -e "${BLUE}--> Initializing system permissions...${NC}"
        sudo -v || { echo -e "${RED}Sudo authentication failed. Some features may not work.${NC}"; }
    fi

    local missing=()
    for cmd in fzf ostree flatpak; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${YELLOW}==========================================${NC}"
        echo -e "${YELLOW}   MISSING DEPENDENCIES DETECTED${NC}"
        echo -e "${YELLOW}==========================================${NC}"
        echo -e "The following tools are missing: ${BLUE}${missing[*]}${NC}"
        echo ""
        read -p "Would you like to try auto-installing them? [Y/n]: " choice
        case "$choice" in
            [yY][eE][sS]|[yY]|"")
                if command -v apt &> /dev/null; then
                    sudo apt update && sudo apt install -y "${missing[@]}"
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y "${missing[@]}"
                elif command -v pacman &> /dev/null; then
                    sudo pacman -S --noconfirm "${missing[@]}"
                elif command -v zypper &> /dev/null; then
                    sudo zypper install -y "${missing[@]}"
                else
                    echo -e "${RED}Could not detect a supported package manager.${NC}"
                    echo -e "Please manually install: ${BLUE}${missing[*]}${NC}"
                    exit 1
                fi
                ;;
            *)
                echo -e "${RED}Cannot proceed without dependencies. Exiting.${NC}"
                exit 1
                ;;
        esac
    fi
}

# =========================================
# 2. AUTO-CONFIGURE FLATHUB & COLLECTION ID
# =========================================
ensure_flathub_remote() {
    if ! flatpak remotes | grep -q "flathub"; then
        echo -e "${BLUE}--> 'flathub' remote missing. Registering Flathub in user scope...${NC}"
        flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null
    fi

    echo -e "${BLUE}--> Ensuring Flathub collection IDs are set...${NC}"
    sudo flatpak remote-modify --collection-id=org.flathub.Stable flathub 2>/dev/null || \
    flatpak remote-modify --user --collection-id=org.flathub.Stable flathub 2>/dev/null
}

# Helper function for live progress rendering
run_with_progress() {
    local app_id="$1"
    shift
    local log_file
    log_file=$(mktemp /tmp/flatpak_usb_XXXXXX.log)
    
    "$@" > "$log_file" 2>&1 &
    local pid=$!
    
    local spin='-\|/'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        local repo_size="0 MB"
        if [ -d "$OSTREE_REPO" ]; then
            repo_size=$(du -sh "$OSTREE_REPO" 2>/dev/null | cut -f1)
        fi
        printf "\r [ %s ] Processing %s... (USB Repo: %s)" "${spin:$i:1}" "$app_id" "$repo_size"
        sleep 0.2
    done
    wait $pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        printf "\r [${GREEN}✔${NC}] Successfully finished %s!                                        \n" "$app_id"
    else
        printf "\r [${RED}✘${NC}] Failed processing %s. See log: %s\n" "$app_id" "$log_file"
        tail -n 5 "$log_file"
    fi
    return $exit_code
}

show_menu() {
    clear
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}    FLATPAK PORTABLE OSTREE MANAGER       ${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo "USB Location: ${USB_DIR}"
    echo -e "${BLUE}==========================================${NC}"
    echo "1) Guide: How to Export Flatpaks TO this USB"
    echo "2) Sideload/Install Flatpaks FROM this USB"
    echo "3) Delete Flatpaks FROM this USB"
    echo "4) Exit"
    echo -e "${BLUE}==========================================${NC}"
    read -p "Select option [1-4]: " choice
    case $choice in
        1) show_export_guide ;;
        2) install_from_usb ;;
        3) delete_from_usb ;;
        4) exit 0 ;;
        *) echo "Invalid choice"; sleep 1; show_menu ;;
    esac
}

show_export_guide() {
    clear
    echo -e "${BLUE}==========================================================================${NC}"
    echo -e "${BLUE}            GUIDE: HOW TO EXPORT FLATPAKS TO THIS USB                    ${NC}"
    echo -e "${BLUE}==========================================================================${NC}"
    echo -e "The 'flatpak create-usb' tool is sensitive to environment settings."
    echo -e "Follow these steps in your terminal to bundle apps reliably:\n"
    
    echo -e "${YELLOW}STEP 1: Prepare the Remote${NC}"
    echo -e "Ensure Flathub is registered and the Collection ID is set (required for USB):"
    echo -e "  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
    echo -e "  flatpak remote-modify --user --collection-id=org.flathub.Stable flathub\n"
    
    echo -e "${YELLOW}STEP 2: Identify the App and its Runtime${NC}"
    echo -e "Get the App ID:  flatpak list --app"
    echo -e "Get the Runtime: flatpak info --show-runtime [APP_ID]\n"
    
    echo -e "${YELLOW}STEP 3: Export the Runtime (CRITICAL)${NC}"
    echo -e "Apps will NOT work on other machines if you skip this. Use the exact runtime string:"
    echo -e "  flatpak create-usb --user \"${USB_DIR}\" runtime/[RUNTIME_ID]\n"
    echo -e "  *(Example: flatpak create-usb --user \"${USB_DIR}\" runtime/org.freedesktop.Platform/x86_64/25.08)*\n"
    
    echo -e "${YELLOW}STEP 4: Export the Application${NC}"
    echo -e "  flatpak create-usb --user \"${USB_DIR}\" [APP_ID]\n"
    
    echo -e "${BLUE}--------------------------------------------------------------------------${NC}"
    echo -e "${RED}COMMON FAILURES & RESOLUTIONS:${NC}"
    echo -e ""
    echo -e "${YELLOW}1. Error: 'Invalid id / Name can't start with ['${NC}"
    echo -e "   Reason: Using square brackets `[...]` in your command triggers bash expansion."
    echo -e "   Fix: Omit the brackets and type the full runtime path cleanly.\n"
    
    echo -e "${YELLOW}2. Error: '... not installed' or Scope Mismatch${NC}"
    echo -e "   Reason: Mixing 'sudo' (system) with user-installed apps."
    echo -e "   Fix: Match your flags. If installed via user, use the `--user` flag instead of `sudo`.\n"
    
    echo -e "${YELLOW}3. Error: 'Collection ID not set'${NC}"
    echo -e "   Reason: The remote isn't configured for P2P distribution."
    echo -e "   Fix: Run the `remote-modify` command in Step 1.\n"
    
    echo -e "${BLUE}==========================================================================${NC}"
    read -p "Press Enter to return to menu..." dummy
    show_menu
}

install_from_usb() {
    echo ""
    if [ ! -d "$OSTREE_REPO" ]; then
        echo -e "${RED}Error: No OSTree repository found on USB (.ostree/repo missing).${NC}"
        read -p "Press Enter to return..." dummy
        show_menu
        return
    fi

    echo -e "${BLUE}--> Reading Flatpaks inside USB OSTree repository...${NC}"

    local raw_usb_apps
    raw_usb_apps=$(find "$OSTREE_REPO/refs" -type f -path "*/app/*" 2>/dev/null | awk -F'/app/' '{print $2}' | cut -d'/' -f1 | sort -u)

    if [ -z "$raw_usb_apps" ]; then
        echo -e "${RED}No applications found inside USB repository.${NC}"
        read -p "Press Enter to return..." dummy
        show_menu
        return
    fi

    local installed_local_apps
    installed_local_apps=$(flatpak list --app --columns=application)

    USB_DISPLAY_LIST=()
    while IFS= read -r app_id; do
        [ -z "$app_id" ] && continue
        if echo "$installed_local_apps" | grep -q "^${app_id}$"; then
            USB_DISPLAY_LIST+=("[INSTALLED]   $app_id")
        else
            USB_DISPLAY_LIST+=("[AVAILABLE]   $app_id")
        fi
    done <<< "$raw_usb_apps"

    echo ""
    echo "[Instructions] Use TAB to select MULTIPLE apps. Press ENTER to confirm."
    echo ""

    SELECTED_RAW=$(printf "%s\n" "${USB_DISPLAY_LIST[@]}" | fzf -m --header="[INSTALLED] = Already on System | Select to Install" --reverse)

    if [ -z "$SELECTED_RAW" ]; then
        echo "No apps selected."
        sleep 1
        show_menu
        return
    fi

    echo ""
    echo -e "${BLUE}--> Sideloading selected Flatpaks from USB...${NC}"
    echo ""

    while IFS= read -r line; do
        tag=$(echo "$line" | awk '{print $1}')
        app_id=$(echo "$line" | awk '{print $2}')

        if [ "$tag" == "[INSTALLED]" ]; then
            echo "--> Skipping $app_id (Already installed on this system)"
        else
            run_with_progress "$app_id" flatpak install --user --sideload-repo="$OSTREE_REPO" flathub "$app_id" -y
        fi
    done <<< "$SELECTED_RAW"

    echo ""
    echo -e "${GREEN}SUCCESS: Operation finished!${NC}"
    read -p "Press Enter to return..." dummy
    show_menu
}

delete_from_usb() {
    echo ""
    if [ ! -d "$OSTREE_REPO" ]; then
        echo -e "${RED}Error: No OSTree repository found on USB (.ostree/repo missing).${NC}"
        read -p "Press Enter to return..." dummy
        show_menu
        return
    fi

    echo -e "${BLUE}--> Reading Flatpaks inside USB OSTree repository...${NC}"

    local raw_usb_apps
    raw_usb_apps=$(find "$OSTREE_REPO/refs" -type f -path "*/app/*" 2>/dev/null | awk -F'/app/' '{print $2}' | cut -d'/' -f1 | sort -u)

    if [ -z "$raw_usb_apps" ]; then
        echo -e "${RED}No applications found inside USB repository to delete.${NC}"
        read -p "Press Enter to return..." dummy
        show_menu
        return
    fi

    echo ""
    echo "[Instructions] Use TAB to select MULTIPLE apps to REMOVE. Press ENTER to confirm."
    echo ""

    SELECTED_RAW=$(printf "%s\n" "${raw_usb_apps[@]}" | fzf -m --header="Select App to DELETE from USB" --reverse)

    if [ -z "$SELECTED_RAW" ]; then
        echo "No apps selected."
        sleep 1
        show_menu
        return
    fi

    echo ""
    echo -e "${RED}--> Removing selected applications from USB...${NC}"
    echo ""

    while IFS= read -r app_id; do
        [ -z "$app_id" ] && continue
        echo "--> Deleting $app_id..."
        find "$OSTREE_REPO/refs" -type f -path "*/app/$app_id/*" -delete 2>/dev/null
        rm -rf "$OSTREE_REPO/refs/heads/app/$app_id" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[✔] Removed $app_id${NC}"
        else
            echo -e "${RED}[✘] Failed to remove $app_id${NC}"
        fi
    done <<< "$SELECTED_RAW"

    echo ""
    echo -e "${GREEN}SUCCESS: Selected applications removed from USB!${NC}"
    read -p "Press Enter to return..." dummy
    show_menu
}

# Auto-run startup checks
check_dependencies
ensure_flathub_remote
show_menu
