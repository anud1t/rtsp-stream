#!/bin/bash

# Common functions for RTSP streaming scripts
# This file contains shared functionality to reduce code duplication

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
RESET='\033[0m'

# Global array to keep track of background process PIDs
declare -a BACKGROUND_PIDS=()

# Function to print colored output
print_error() {
    echo -e "${RED}Error: $1${RESET}" >&2
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${RESET}" >&2
}

print_info() {
    echo -e "${BLUE}Info: $1${RESET}"
}

print_success() {
    echo -e "${GREEN}Success: $1${RESET}"
}

print_header() {
    echo -e "${CYAN}${BOLD}=========================================${RESET}"
    echo -e "${CYAN}${BOLD}      RTSP Streaming System              ${RESET}"
    echo -e "${CYAN}${BOLD}=========================================${RESET}"
}

# Function to handle cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${RESET}"

    # Kill any background processes
    if [ ${#BACKGROUND_PIDS[@]} -ne 0 ]; then
        for pid in "${BACKGROUND_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${YELLOW}Terminating process with PID $pid${RESET}"
                kill "$pid"
            fi
        done
    fi

    echo -e "${GREEN}Cleanup complete. Exiting.${RESET}"
}

# Trap signals and call cleanup
trap cleanup EXIT INT TERM

# Function to check and install dependencies
check_install() {
    local pkg="$1"
    local cmd="$2"
    local install_cmd="$3"

    if ! command -v "$cmd" &> /dev/null; then
        print_error "$pkg is not installed."
        read -p "Do you want to install $pkg? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            print_info "Installing $pkg..."
            sudo apt-get update
            sudo apt-get install -y $install_cmd
        else
            print_error "Cannot proceed without $pkg. Exiting."
            exit 1
        fi
    else
        print_success "$pkg is installed."
    fi
}

# Function to get the Tailscale IP
get_tailscale_ip() {
    if command -v tailscale &> /dev/null; then
        TAILSCALE_IP=$(tailscale ip -4)
        echo "$TAILSCALE_IP"
    else
        echo ""
    fi
}

# Function to get local IP
get_local_ip() {
    local ip_addr
    ip_addr=$(hostname -I | awk '{print $1}')
    if [ -z "$ip_addr" ]; then
        print_warning "Could not automatically determine local IP address."
        echo "127.0.0.1" # Fallback
    else
        echo "$ip_addr"
    fi
}

# Function to list video devices
list_video_devices() {
    print_info "Detecting connected video devices..."
    local index=1
    local device_list=()
    local device_types=()

    for device in /dev/video*; do
        if [ -c "$device" ]; then
            local driver_info=$(v4l2-ctl --device="$device" --all 2>/dev/null)
            local device_type="USB Camera"
            
            if echo "$driver_info" | grep -q "Driver name[[:space:]]*:[[:space:]]*tegra-video" && \
               echo "$driver_info" | grep -q "Card type[[:space:]]*:[[:space:]]*vi-output, isx031"; then
                device_type="STURDECAM"
            fi

            local device_name=$(udevadm info --query=all --name="$device" | grep 'ID_V4L_PRODUCT=' | cut -d'=' -f2)
            device_list+=("$device")
            device_types+=("$device_type")
            echo "$index. $device (${device_name:-Unknown Device}) - $device_type"
            ((index++))
        fi
    done

    if [ ${#device_list[@]} -eq 0 ]; then
        print_error "No video devices found."
        return 1
    fi

    # Export arrays for use in calling script
    DEVICE_LIST=("${device_list[@]}")
    DEVICE_TYPES=("${device_types[@]}")
    return 0
}

# Function to validate resolution input
validate_resolution() {
    local resolution="$1"
    if [[ "$resolution" =~ ^[0-9]+x[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to parse resolution
parse_resolution() {
    local resolution="$1"
    WIDTH=$(echo "$resolution" | cut -d'x' -f1)
    HEIGHT=$(echo "$resolution" | cut -d'x' -f2)
}

# Function to check if port is available
check_port() {
    local port="$1"
    if netstat -tuln | grep -q ":$port "; then
        return 1  # Port is in use
    else
        return 0  # Port is available
    fi
}

# Function to wait for process to start
wait_for_process() {
    local pid="$1"
    local timeout="${2:-5}"
    local count=0
    
    while [ $count -lt $timeout ]; do
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        sleep 1
        ((count++))
    done
    return 1
}

# Function to add process to background tracking
add_background_process() {
    local pid="$1"
    BACKGROUND_PIDS+=("$pid")
}

# Function to remove process from background tracking
remove_background_process() {
    local pid="$1"
    local new_pids=()
    for bg_pid in "${BACKGROUND_PIDS[@]}"; do
        if [ "$bg_pid" != "$pid" ]; then
            new_pids+=("$bg_pid")
        fi
    done
    BACKGROUND_PIDS=("${new_pids[@]}")
}
