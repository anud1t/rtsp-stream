#!/bin/bash

# Main RTSP Streaming Script
# Unified script for streaming cameras and video files over RTSP

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Configuration
DEFAULT_PORT="8554"
DEFAULT_RESOLUTION="1280x720"
DEFAULT_FRAMERATE="30"

# Global variables
SELECTED_CAMERAS=()
SELECTED_DEVICE_TYPES=()
VIDEO_FILES=()
STREAM_NAMES=()
VIDEO_STREAM_NAMES=()
WIDTH=""
HEIGHT=""
STURDECAM_WIDTH=""
STURDECAM_HEIGHT=""
RTSP_IP=""
STREAM_TO_LOCALHOST=""

print_header

# Check for required dependencies
print_info "Checking for required dependencies..."

# GStreamer
check_install "GStreamer" "gst-launch-1.0" "gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav"

# v4l2-utils for camera
check_install "v4l-utils" "v4l2-ctl" "v4l-utils"

# Check for gst-rtsp-server
if ! pkg-config --exists gstreamer-rtsp-server-1.0; then
    print_error "gst-rtsp-server development packages not found."
    read -p "Do you want to install gst-rtsp-server? (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        print_info "Installing gst-rtsp-server..."
        sudo apt-get update
        sudo apt-get install -y libgstrtspserver-1.0-dev gstreamer1.0-rtsp libglib2.0-dev
    else
        print_error "Cannot proceed without gst-rtsp-server. Exiting."
        exit 1
    fi
fi

# Compile multi-stream-server if needed
if [ ! -f "$SCRIPT_DIR/jetson/multi-stream-server-unified" ]; then
    print_info "Compiling multi-stream-server-unified..."
    make -C "$SCRIPT_DIR" || {
        print_error "Failed to compile multi-stream-server-unified"
        exit 1
    }
fi

# Get Tailscale IP
TAILSCALE_IP=$(get_tailscale_ip)
if [ -n "$TAILSCALE_IP" ]; then
    print_success "Tailscale is running. IP: $TAILSCALE_IP"
else
    print_warning "Tailscale is not installed or not running."
fi

# Helper functions (defined before they're used)
select_cameras() {
    echo -e "${YELLOW}Please select up to 4 cameras (separated by spaces):${RESET}"
    read -p "Enter the numbers of the cameras you want to use: " CAMERA_CHOICES

    # Convert input to an array
    IFS=' ' read -r -a SELECTED_INDICES <<< "$CAMERA_CHOICES"

    # Validate selections
    VALID_SELECTIONS=()
    for choice in "${SELECTED_INDICES[@]}"; do
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le ${#DEVICE_LIST[@]} ]]; then
            VALID_SELECTIONS+=("$choice")
        else
            print_error "Invalid selection: $choice. Skipping."
        fi
    done

    # Limit to 4 cameras
    if [ ${#VALID_SELECTIONS[@]} -gt 4 ]; then
        VALID_SELECTIONS=("${VALID_SELECTIONS[@]:0:4}")
        print_warning "You can select up to 4 cameras. Only the first 4 selections will be used."
    fi

    if [ ${#VALID_SELECTIONS[@]} -eq 0 ]; then
        print_error "No valid camera selections made."
        return 1
    fi

    SELECTED_CAMERAS=()
    SELECTED_DEVICE_TYPES=()
    for idx in "${VALID_SELECTIONS[@]}"; do
        SELECTED_CAMERAS+=("${DEVICE_LIST[$((idx-1))]}")
        SELECTED_DEVICE_TYPES+=("${DEVICE_TYPES[$((idx-1))]}")
    done

    if [ ${#SELECTED_CAMERAS[@]} -gt 0 ]; then
        print_success "You have selected the following cameras:"
        for i in "${!SELECTED_CAMERAS[@]}"; do
            echo "- ${SELECTED_CAMERAS[$i]} (${SELECTED_DEVICE_TYPES[$i]})"
        done
    fi
}

select_video_files() {
    echo -e "${YELLOW}Please enter up to 4 video file paths.${RESET}"
    VIDEO_FILES=()
    VIDEO_STREAM_NAMES=()
    for i in {1..4}; do
        read -p "Enter path for video file $i (or leave blank to finish): " VIDEO_FILE_PATH
        if [ -z "$VIDEO_FILE_PATH" ]; then
            break
        elif [ ! -f "$VIDEO_FILE_PATH" ]; then
            print_error "File does not exist. Please enter a valid file path."
            ((i--))
            continue
        else
            VIDEO_FILES+=("$VIDEO_FILE_PATH")
            # Ask for endpoint label
            DEFAULT_STREAM_NAME="video$i"
            echo -e "${YELLOW}Default stream name for $VIDEO_FILE_PATH: $DEFAULT_STREAM_NAME${RESET}"
            read -p "Enter the stream name for $VIDEO_FILE_PATH [$DEFAULT_STREAM_NAME]: " STREAM_NAME
            STREAM_NAME=${STREAM_NAME:-$DEFAULT_STREAM_NAME}
            VIDEO_STREAM_NAMES+=("$STREAM_NAME")
        fi
    done

    if [ ${#VIDEO_FILES[@]} -eq 0 ]; then
        print_error "No video files selected."
    else
        print_success "You have selected the following video files:"
        for vid in "${VIDEO_FILES[@]}"; do
            echo "- $vid"
        done
    fi
}

select_resolution() {
    echo -e "${YELLOW}Available resolutions:${RESET}"
    RESOLUTIONS=("1920x1080" "1280x720" "640x480" "Custom")
    for i in "${!RESOLUTIONS[@]}"; do
        echo "$((i+1)). ${RESOLUTIONS[$i]}"
    done

    read -p "Select the output resolution [2]: " RES_CHOICE
    RES_CHOICE=${RES_CHOICE:-2}

    while ! [[ "$RES_CHOICE" =~ ^[1-9][0-9]*$ ]] || [[ "$RES_CHOICE" -gt ${#RESOLUTIONS[@]} ]]; do
        print_error "Invalid selection. Please enter a valid number."
        read -p "Select the output resolution [2]: " RES_CHOICE
        RES_CHOICE=${RES_CHOICE:-2}
    done

    if [ "${RESOLUTIONS[$((RES_CHOICE-1))]}" == "Custom" ]; then
        read -p "Enter custom width: " CUSTOM_WIDTH
        read -p "Enter custom height: " CUSTOM_HEIGHT
        WIDTH="$CUSTOM_WIDTH"
        HEIGHT="$CUSTOM_HEIGHT"
    else
        SELECTED_RESOLUTION="${RESOLUTIONS[$((RES_CHOICE-1))]}"
        parse_resolution "$SELECTED_RESOLUTION"
    fi
    print_success "You have selected resolution: ${WIDTH}x${HEIGHT}"
}

select_sturdecam_resolution() {
    echo -e "${YELLOW}STURDECAM resolution options:${RESET}"
    STURDECAM_RESOLUTIONS=("1920x1536 (Native)" "1920x1080 (1080p)" "1280x720 (720p)" "Custom")
    for i in "${!STURDECAM_RESOLUTIONS[@]}"; do
        echo "$((i+1)). ${STURDECAM_RESOLUTIONS[$i]}"
    done

    read -p "Select the STURDECAM resolution [1]: " STURDECAM_RES_CHOICE
    STURDECAM_RES_CHOICE=${STURDECAM_RES_CHOICE:-1}

    while ! [[ "$STURDECAM_RES_CHOICE" =~ ^[1-9][0-9]*$ ]] || [[ "$STURDECAM_RES_CHOICE" -gt ${#STURDECAM_RESOLUTIONS[@]} ]]; do
        print_error "Invalid selection. Please enter a valid number."
        read -p "Select the STURDECAM resolution [1]: " STURDECAM_RES_CHOICE
        STURDECAM_RES_CHOICE=${STURDECAM_RES_CHOICE:-1}
    done

    case $STURDECAM_RES_CHOICE in
        1) STURDECAM_WIDTH=1920; STURDECAM_HEIGHT=1536 ;;
        2) STURDECAM_WIDTH=1920; STURDECAM_HEIGHT=1080 ;;
        3) STURDECAM_WIDTH=1280; STURDECAM_HEIGHT=720 ;;
        4)
            read -p "Enter custom STURDECAM width: " CUSTOM_STURDECAM_WIDTH
            read -p "Enter custom STURDECAM height: " CUSTOM_STURDECAM_HEIGHT
            STURDECAM_WIDTH="$CUSTOM_STURDECAM_WIDTH"
            STURDECAM_HEIGHT="$CUSTOM_STURDECAM_HEIGHT"
            ;;
    esac
    print_success "STURDECAM will stream at: ${STURDECAM_WIDTH}x${STURDECAM_HEIGHT}"
}

start_gstreamer_pipelines() {
    echo ""
    print_info "Starting the GStreamer pipelines..."
    echo ""

    # Arrays to store mount points and pipelines
    MOUNT_POINTS=()
    PIPELINES=()

    # Handle cameras
    if [ ${#SELECTED_CAMERAS[@]} -gt 0 ]; then
        for i in "${!SELECTED_CAMERAS[@]}"; do
            device="${SELECTED_CAMERAS[$i]}"
            DEVICE_TYPE="${SELECTED_DEVICE_TYPES[$i]}"
            echo "----------------------------------------"
            print_info "Configuring stream for device: $device ($DEVICE_TYPE)"
            echo ""

            # Set default stream name
            if [ "$DEVICE_TYPE" == "STURDECAM" ]; then
                DEFAULT_STREAM_NAME="sturdecam$((i+1))"
            else
                DEFAULT_STREAM_NAME="cam$((i+1))"
            fi

            echo -e "${YELLOW}Default stream name for $device: $DEFAULT_STREAM_NAME${RESET}"
            read -p "Enter the stream name for $device [$DEFAULT_STREAM_NAME]: " STREAM_NAME
            STREAM_NAME=${STREAM_NAME:-$DEFAULT_STREAM_NAME}
            STREAM_NAMES+=("$STREAM_NAME")
            echo ""

            if [ "$DEVICE_TYPE" == "STURDECAM" ]; then
                # Hardware acceleration pipeline for STURDECAM
                STURDECAM_WIDTH=${STURDECAM_WIDTH:-1920}
                STURDECAM_HEIGHT=${STURDECAM_HEIGHT:-1536}

                SOURCE_PIPELINE="v4l2src device=$device ! video/x-raw, width=$STURDECAM_WIDTH, height=$STURDECAM_HEIGHT, format=UYVY"
                COMMON_PIPELINE="videoconvert ! nvvidconv ! video/x-raw(memory:NVMM), format=I420"
                ENCODER_PIPELINE="nvv4l2h264enc bitrate=10000000"
                SINK_PIPELINE="h264parse ! rtph264pay config-interval=1 pt=96 name=pay0"
                FULL_PIPELINE="${SOURCE_PIPELINE} ! ${COMMON_PIPELINE} ! ${ENCODER_PIPELINE} ! ${SINK_PIPELINE}"
            else
                # Software encoding pipeline for USB Camera
                SOURCE_PIPELINE="v4l2src device=$device ! image/jpeg, width=$WIDTH, height=$HEIGHT ! jpegdec ! videoconvert"
                COMMON_PIPELINE="videoscale ! video/x-raw,format=I420"
                ENCODER_PIPELINE="x264enc tune=zerolatency speed-preset=ultrafast"
                SINK_PIPELINE="h264parse ! rtph264pay config-interval=1 pt=96 name=pay0"
                FULL_PIPELINE="${SOURCE_PIPELINE} ! ${COMMON_PIPELINE} ! ${ENCODER_PIPELINE} ! ${SINK_PIPELINE}"
            fi

            # Add to arrays
            MOUNT_POINTS+=("/$STREAM_NAME")
            PIPELINES+=("$FULL_PIPELINE")
        done
    fi

    # Handle video files
    if [ ${#VIDEO_FILES[@]} -gt 0 ]; then
        for i in "${!VIDEO_FILES[@]}"; do
            VIDEO_FILE="${VIDEO_FILES[$i]}"
            STREAM_NAME="${VIDEO_STREAM_NAMES[$i]}"

            SOURCE_PIPELINE="filesrc location=\"${VIDEO_FILE}\" ! qtdemux ! h264parse ! nvv4l2decoder ! nvvidconv"
            ENCODER_PIPELINE="nvv4l2h264enc bitrate=10000000 ! h264parse"
            SINK_PIPELINE="rtph264pay config-interval=1 pt=96 name=pay0"
            FULL_PIPELINE="${SOURCE_PIPELINE} ! ${ENCODER_PIPELINE} ! ${SINK_PIPELINE}"

            # Add to arrays
            MOUNT_POINTS+=("/$STREAM_NAME")
            PIPELINES+=("$FULL_PIPELINE")
        done
    fi

    # Check if there are any streams to start
    if [ ${#MOUNT_POINTS[@]} -eq 0 ]; then
        print_error "No streams to start."
        exit 1
    fi

    # Build arguments for multi-stream-server
    SERVER_ARGS=()
    for i in "${!MOUNT_POINTS[@]}"; do
        SERVER_ARGS+=("${MOUNT_POINTS[$i]}")
        SERVER_ARGS+=("${PIPELINES[$i]}")
    done

    # Start the RTSP server(s) based on user choice
    echo "========================================"
    case $STREAM_TO_LOCALHOST in
        "single")
            print_info "Starting RTSP server with multiple streams..."
            echo ""
            "$SCRIPT_DIR/jetson/multi-stream-server-unified" "${SERVER_ARGS[@]}" &
            RTSP_SERVER_PID=$!
            add_background_process "$RTSP_SERVER_PID"

            print_success "RTSP server started with PID $RTSP_SERVER_PID"
            echo ""
            echo "Stream URLs:"
            for mount_point in "${MOUNT_POINTS[@]}"; do
                echo -e "  ${CYAN}rtsp://$RTSP_IP:8554${mount_point}${RESET}"
                echo -e "  ${CYAN}rtsp://localhost:8554${mount_point}${RESET}"
            done
            echo ""
            ;;
        "separate")
            print_info "Starting external RTSP server on port 8554..."
            echo ""
            "$SCRIPT_DIR/jetson/multi-stream-server-unified" "${SERVER_ARGS[@]}" &
            RTSP_SERVER_PID=$!
            add_background_process "$RTSP_SERVER_PID"

            print_success "External RTSP server started with PID $RTSP_SERVER_PID"
            echo ""
            print_info "Starting localhost RTSP server on port 8555..."
            "$SCRIPT_DIR/jetson/multi-stream-server-unified" --port 8555 "${SERVER_ARGS[@]}" &
            LOCALHOST_SERVER_PID=$!
            add_background_process "$LOCALHOST_SERVER_PID"
            
            print_success "Localhost RTSP server started with PID $LOCALHOST_SERVER_PID"
            echo ""
            echo "Stream URLs:"
            for mount_point in "${MOUNT_POINTS[@]}"; do
                echo -e "  ${CYAN}External: rtsp://$RTSP_IP:8554${mount_point}${RESET}"
                echo -e "  ${CYAN}Localhost: rtsp://localhost:8555${mount_point}${RESET}"
            done
            echo ""
            ;;
        "external")
            print_info "Starting RTSP server with multiple streams..."
            echo ""
            "$SCRIPT_DIR/jetson/multi-stream-server-unified" "${SERVER_ARGS[@]}" &
            RTSP_SERVER_PID=$!
            add_background_process "$RTSP_SERVER_PID"

            print_success "RTSP server started with PID $RTSP_SERVER_PID"
            echo ""
            echo "Stream URLs:"
            for mount_point in "${MOUNT_POINTS[@]}"; do
                echo -e "  ${CYAN}rtsp://$RTSP_IP:8554${mount_point}${RESET}"
            done
            echo ""
            ;;
    esac

    # Wait for the RTSP server process
    wait $RTSP_SERVER_PID
    exit 0
}

# User Interaction
print_info "Configuring the streaming settings..."

# Ask user what they want to stream
echo -e "${CYAN}What do you want to stream?${RESET}"
echo "1. Cameras"
echo "2. Video Files"
echo "3. Both Cameras and Video Files"
read -p "Enter your choice [1]: " STREAM_CHOICE
STREAM_CHOICE=${STREAM_CHOICE:-1}

while ! [[ "$STREAM_CHOICE" =~ ^[1-3]$ ]]; do
    print_error "Invalid selection. Please enter 1, 2, or 3."
    read -p "Enter your choice [1]: " STREAM_CHOICE
    STREAM_CHOICE=${STREAM_CHOICE:-1}
done

# Handle camera selection
if [ "$STREAM_CHOICE" -eq 1 ] || [ "$STREAM_CHOICE" -eq 3 ]; then
    if list_video_devices; then
        select_cameras
    else
        print_error "No cameras available."
        if [ "$STREAM_CHOICE" -eq 1 ]; then
            exit 1
        fi
    fi
fi

# Handle video file selection
if [ "$STREAM_CHOICE" -eq 2 ] || [ "$STREAM_CHOICE" -eq 3 ]; then
    select_video_files
fi

if [ ${#SELECTED_CAMERAS[@]} -eq 0 ] && [ ${#VIDEO_FILES[@]} -eq 0 ]; then
    print_error "No cameras or video files selected. Exiting."
    exit 1
fi

# Resolution selection
select_resolution

# STURDECAM resolution selection if needed
if [[ " ${SELECTED_DEVICE_TYPES[@]} " =~ " STURDECAM " ]]; then
    select_sturdecam_resolution
fi

# RTSP server configuration
DEFAULT_IP="${TAILSCALE_IP:-$(get_local_ip)}"
print_info "Default RTSP server IP: $DEFAULT_IP"
read -p "Enter the RTSP server IP [$DEFAULT_IP]: " RTSP_IP
RTSP_IP=${RTSP_IP:-$DEFAULT_IP}

# Localhost streaming options
echo -e "${CYAN}Localhost streaming options:${RESET}"
echo "1. Single server (accessible on both $RTSP_IP and localhost)"
echo "2. Separate servers (external IP on port 8554, localhost on port 8555)"
echo "3. External IP only"
read -p "Enter your choice [1]: " LOCALHOST_CHOICE
LOCALHOST_CHOICE=${LOCALHOST_CHOICE:-1}

case $LOCALHOST_CHOICE in
    1) STREAM_TO_LOCALHOST="single" ;;
    2) STREAM_TO_LOCALHOST="separate" ;;
    3) STREAM_TO_LOCALHOST="external" ;;
    *) STREAM_TO_LOCALHOST="single" ;;
esac

# Start streaming
start_gstreamer_pipelines
