#!/bin/bash

# Script: rtsp_stream.sh -- anudi.gautam@herculesdynamics.com

# Description: Stream multiple cameras and video files using GStreamer over RTSP using gst-rtsp-server.

# Uses hardware acceleration for STURDECAMs and video files, and software encoding for USB cameras.

set +H

# Global array to keep track of background process PIDs
declare -a BACKGROUND_PIDS=()

# Arrays to store selected formats and stream names
declare -a SELECTED_FORMATS=()
declare -a STREAM_NAMES=()
declare -a VIDEO_STREAM_NAMES=()

# Arrays to store device types
declare -a DEVICE_TYPES=()  # STURDECAM or USB

# Function to handle cleanup on exit
cleanup() {
    echo -e "\n\e[33mCleaning up...\e[0m"

    # Kill any background processes
    if [ ${#BACKGROUND_PIDS[@]} -ne 0 ]; then
        for pid in "${BACKGROUND_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "\e[33mTerminating process with PID $pid\e[0m"
                kill "$pid"
            fi
        done
    fi

    echo -e "\e[32mCleanup complete. Exiting.\e[0m"
}

# Trap signals and call cleanup
trap cleanup EXIT INT TERM

# Function to check and install dependencies
check_install() {
    local pkg="$1"
    local cmd="$2"
    local install_cmd="$3"

    if ! command -v "$cmd" &> /dev/null; then
        echo -e "\e[31m$pkg is not installed.\e[0m"
        read -p "Do you want to install $pkg? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            echo -e "\e[33mInstalling $pkg...\e[0m"
            sudo apt-get update
            sudo apt-get install -y $install_cmd
        else
            echo -e "\e[31mCannot proceed without $pkg. Exiting.\e[0m"
            exit 1
        fi
    else
        echo -e "\e[32m$pkg is installed.\e[0m"
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

# Function to print a header
print_header() {
    echo -e "\e[1;36m=========================================\e[0m"
    echo -e "\e[1;36m      Multi-Stream Streaming Script      \e[0m"
    echo -e "\e[1;36m=========================================\e[0m"
}

# Function to list video devices and classify them
list_video_devices() {
    echo -e "\e[33mDetecting connected video devices...\e[0m"
    index=1
    DEVICE_LIST=()
    DEVICE_TYPES=()

    for device in /dev/video*; do
        if [ -c "$device" ]; then
            driver_info=$(v4l2-ctl --device="$device" --all 2>/dev/null)
            if echo "$driver_info" | grep -q "Driver name[[:space:]]*:[[:space:]]*tegra-video" && \
               echo "$driver_info" | grep -q "Card type[[:space:]]*:[[:space:]]*vi-output, isx031"; then
                DEVICE_TYPE="STURDECAM"
            else
                DEVICE_TYPE="USB Camera"
            fi

            DEVICE_NAME=$(udevadm info --query=all --name="$device" | grep 'ID_V4L_PRODUCT=' | cut -d'=' -f2)
            DEVICE_LIST+=("$device")
            DEVICE_TYPES+=("$DEVICE_TYPE")
            echo "$index. $device (${DEVICE_NAME:-Unknown Device}) - $DEVICE_TYPE"
            ((index++))
        fi
    done

    if [ ${#DEVICE_LIST[@]} -eq 0 ]; then
        echo -e "\e[31mNo video devices found.\e[0m"
        exit 1
    fi
}

# Function to select cameras
select_cameras() {
    echo -e "\e[33mPlease select up to 4 cameras (separated by spaces):\e[0m"
    read -p "Enter the numbers of the cameras you want to use: " CAMERA_CHOICES

    # Convert input to an array
    IFS=' ' read -r -a SELECTED_INDICES <<< "$CAMERA_CHOICES"

    # Validate selections
    VALID_SELECTIONS=()
    for choice in "${SELECTED_INDICES[@]}"; do
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le ${#DEVICE_LIST[@]} ]]; then
            VALID_SELECTIONS+=("$choice")
        else
            echo -e "\e[31mInvalid selection: $choice. Skipping.\e[0m"
        fi
    done

    # Limit to 4 cameras
    if [ ${#VALID_SELECTIONS[@]} -gt 4 ]; then
        VALID_SELECTIONS=("${VALID_SELECTIONS[@]:0:4}")
        echo -e "\e[33mYou can select up to 4 cameras. Only the first 4 selections will be used.\e[0m"
    fi

    if [ ${#VALID_SELECTIONS[@]} -eq 0 ]; then
        echo -e "\e[31mNo valid camera selections made.\e[0m"
    fi

    SELECTED_CAMERAS=()
    SELECTED_DEVICE_TYPES=()
    for idx in "${VALID_SELECTIONS[@]}"; do
        SELECTED_CAMERAS+=("${DEVICE_LIST[$((idx-1))]}")
        SELECTED_DEVICE_TYPES+=("${DEVICE_TYPES[$((idx-1))]}")
    done

    if [ ${#SELECTED_CAMERAS[@]} -gt 0 ]; then
        echo -e "\e[32mYou have selected the following cameras:\e[0m"
        for i in "${!SELECTED_CAMERAS[@]}"; do
            echo "- ${SELECTED_CAMERAS[$i]} (${SELECTED_DEVICE_TYPES[$i]})"
        done
    fi
}

# Function to select video files
select_video_files() {
    echo -e "\e[33mPlease enter up to 4 video file paths.\e[0m"
    VIDEO_FILES=()
    VIDEO_STREAM_NAMES=()
    for i in {1..4}; do
        read -p "Enter path for video file $i (or leave blank to finish): " VIDEO_FILE_PATH
        if [ -z "$VIDEO_FILE_PATH" ]; then
            break
        elif [ ! -f "$VIDEO_FILE_PATH" ]; then
            echo -e "\e[31mFile does not exist. Please enter a valid file path.\e[0m"
            ((i--))
            continue
        else
            VIDEO_FILES+=("$VIDEO_FILE_PATH")
            # Ask for endpoint label
            DEFAULT_STREAM_NAME="video$i"
            echo -e "\e[33mDefault stream name for $VIDEO_FILE_PATH: $DEFAULT_STREAM_NAME\e[0m"
            read -p "Enter the stream name for $VIDEO_FILE_PATH [$DEFAULT_STREAM_NAME]: " STREAM_NAME
            STREAM_NAME=${STREAM_NAME:-$DEFAULT_STREAM_NAME}
            VIDEO_STREAM_NAMES+=("$STREAM_NAME")
        fi
    done

    if [ ${#VIDEO_FILES[@]} -eq 0 ]; then
        echo -e "\e[31mNo video files selected.\e[0m"
    else
        echo -e "\e[32mYou have selected the following video files:\e[0m"
        for vid in "${VIDEO_FILES[@]}"; do
            echo "- $vid"
        done
    fi
}

# Function to select resolution
select_resolution() {
    echo -e "\e[33mAvailable resolutions:\e[0m"
    RESOLUTIONS=("1920x1080" "1280x720" "640x480" "Custom")
    for i in "${!RESOLUTIONS[@]}"; do
        echo "$((i+1)). ${RESOLUTIONS[$i]}"
    done

    read -p "Select the output resolution [2]: " RES_CHOICE
    RES_CHOICE=${RES_CHOICE:-2}

    while ! [[ "$RES_CHOICE" =~ ^[1-9][0-9]*$ ]] || [[ "$RES_CHOICE" -gt ${#RESOLUTIONS[@]} ]]; do
        echo -e "\e[31mInvalid selection. Please enter a valid number.\e[0m"
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
        WIDTH=$(echo "$SELECTED_RESOLUTION" | cut -d'x' -f1)
        HEIGHT=$(echo "$SELECTED_RESOLUTION" | cut -d'x' -f2)
    fi
    echo -e "\e[32mYou have selected resolution: ${WIDTH}x${HEIGHT}\e[0m"
}

# Function to select STURDECAM resolution
select_sturdecam_resolution() {
    echo -e "\e[33mSTURDECAM resolution options:\e[0m"
    STURDECAM_RESOLUTIONS=("1920x1536 (Native)" "1920x1080 (1080p)" "1280x720 (720p)" "Custom")
    for i in "${!STURDECAM_RESOLUTIONS[@]}"; do
        echo "$((i+1)). ${STURDECAM_RESOLUTIONS[$i]}"
    done

    read -p "Select the STURDECAM resolution [1]: " STURDECAM_RES_CHOICE
    STURDECAM_RES_CHOICE=${STURDECAM_RES_CHOICE:-1}

    while ! [[ "$STURDECAM_RES_CHOICE" =~ ^[1-9][0-9]*$ ]] || [[ "$STURDECAM_RES_CHOICE" -gt ${#STURDECAM_RESOLUTIONS[@]} ]]; do
        echo -e "\e[31mInvalid selection. Please enter a valid number.\e[0m"
        read -p "Select the STURDECAM resolution [1]: " STURDECAM_RES_CHOICE
        STURDECAM_RES_CHOICE=${STURDECAM_RES_CHOICE:-1}
    done

    case $STURDECAM_RES_CHOICE in
        1)
            STURDECAM_WIDTH=1920
            STURDECAM_HEIGHT=1536
            echo -e "\e[32mSTURDECAM will stream at native resolution: ${STURDECAM_WIDTH}x${STURDECAM_HEIGHT}\e[0m"
            ;;
        2)
            STURDECAM_WIDTH=1920
            STURDECAM_HEIGHT=1080
            echo -e "\e[32mSTURDECAM will stream at 1080p: ${STURDECAM_WIDTH}x${STURDECAM_HEIGHT}\e[0m"
            ;;
        3)
            STURDECAM_WIDTH=1280
            STURDECAM_HEIGHT=720
            echo -e "\e[32mSTURDECAM will stream at 720p: ${STURDECAM_WIDTH}x${STURDECAM_HEIGHT}\e[0m"
            ;;
        4)
            read -p "Enter custom STURDECAM width: " CUSTOM_STURDECAM_WIDTH
            read -p "Enter custom STURDECAM height: " CUSTOM_STURDECAM_HEIGHT
            STURDECAM_WIDTH="$CUSTOM_STURDECAM_WIDTH"
            STURDECAM_HEIGHT="$CUSTOM_STURDECAM_HEIGHT"
            echo -e "\e[32mSTURDECAM will stream at custom resolution: ${STURDECAM_WIDTH}x${STURDECAM_HEIGHT}\e[0m"
            ;;
    esac
}

# Function to select streaming protocol (set to RTSP)
select_streaming_protocol() {
    STREAM_PROTOCOL="RTSP"
    echo -e "\e[32mStreaming protocol set to: $STREAM_PROTOCOL\e[0m"
}

# Function to start the GStreamer pipelines for all streams
start_gstreamer_pipelines() {
    echo -e "\e[33mStarting the GStreamer pipelines...\e[0m"

    # Arrays to store mount points and pipelines
    MOUNT_POINTS=()
    PIPELINES=()

    # Handle cameras
    if [ ${#SELECTED_CAMERAS[@]} -gt 0 ]; then
        for i in "${!SELECTED_CAMERAS[@]}"; do
            device="${SELECTED_CAMERAS[$i]}"
            DEVICE_TYPE="${SELECTED_DEVICE_TYPES[$i]}"
            echo -e "\e[33mConfiguring stream for device: $device ($DEVICE_TYPE)\e[0m"

            # Set default stream name
            if [ "$DEVICE_TYPE" == "STURDECAM" ]; then
                DEFAULT_STREAM_NAME="sturdecam$((i+1))"
            else
                DEFAULT_STREAM_NAME="cam$((i+1))"
            fi

            echo -e "\e[33mDefault stream name for $device: $DEFAULT_STREAM_NAME\e[0m"
            read -p "Enter the stream name for $device [$DEFAULT_STREAM_NAME]: " STREAM_NAME
            STREAM_NAME=${STREAM_NAME:-$DEFAULT_STREAM_NAME}
            STREAM_NAMES+=("$STREAM_NAME")

            if [ "$DEVICE_TYPE" == "STURDECAM" ]; then
                # Hardware acceleration pipeline for STURDECAM
                # Use the selected STURDECAM resolution (default to native if not set)
                STURDECAM_WIDTH=${STURDECAM_WIDTH:-1920}
                STURDECAM_HEIGHT=${STURDECAM_HEIGHT:-1536}

                SOURCE_PIPELINE="v4l2src device=$device ! video/x-raw, width=$STURDECAM_WIDTH, height=$STURDECAM_HEIGHT, format=UYVY"

                # Common pipeline components
                COMMON_PIPELINE="videoconvert ! nvvidconv ! video/x-raw(memory:NVMM), format=I420"

                # Encoder pipeline
                ENCODER_PIPELINE="nvv4l2h264enc bitrate=10000000"

                # Sink pipeline for RTSP
                SINK_PIPELINE="h264parse ! rtph264pay config-interval=1 pt=96 name=pay0"

                # Build the full pipeline
                FULL_PIPELINE="${SOURCE_PIPELINE} ! ${COMMON_PIPELINE} ! ${ENCODER_PIPELINE} ! ${SINK_PIPELINE}"
            else
                # Software encoding pipeline for USB Camera
                SOURCE_PIPELINE="v4l2src device=$device ! image/jpeg, width=$WIDTH, height=$HEIGHT ! jpegdec ! videoconvert"

                # Common pipeline components
                COMMON_PIPELINE="videoscale ! video/x-raw,format=I420"

                # Encoder pipeline
                ENCODER_PIPELINE="x264enc tune=zerolatency speed-preset=ultrafast"

                # Sink pipeline
                SINK_PIPELINE="h264parse ! rtph264pay config-interval=1 pt=96 name=pay0"

                # Build the full pipeline
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

            # Build the pipeline similar to your working pipeline
            SOURCE_PIPELINE="filesrc location=\"${VIDEO_FILE}\" ! qtdemux ! h264parse ! nvv4l2decoder ! nvvidconv"

            # Encoder pipeline
            ENCODER_PIPELINE="nvv4l2h264enc bitrate=10000000 ! h264parse"

            # Sink pipeline for RTSP
            SINK_PIPELINE="rtph264pay config-interval=1 pt=96 name=pay0"

            # Build the full pipeline
            FULL_PIPELINE="${SOURCE_PIPELINE} ! ${ENCODER_PIPELINE} ! ${SINK_PIPELINE}"

            # Add to arrays
            MOUNT_POINTS+=("/$STREAM_NAME")
            PIPELINES+=("$FULL_PIPELINE")
        done
    fi

    # Check if there are any streams to start
    if [ ${#MOUNT_POINTS[@]} -eq 0 ]; then
        echo -e "\e[31mNo streams to start.\e[0m"
        exit 1
    fi

    # Build arguments for multi-stream-server
    SERVER_ARGS=()
    for i in "${!MOUNT_POINTS[@]}"; do
        SERVER_ARGS+=("${MOUNT_POINTS[$i]}")
        SERVER_ARGS+=("${PIPELINES[$i]}")
    done

    # Start the RTSP server(s) based on user choice
    case $STREAM_TO_LOCALHOST in
        "single")
            # Single server accessible on both IPs
            echo -e "\e[33mStarting RTSP server with multiple streams...\e[0m"
            ./multi-stream-server "${SERVER_ARGS[@]}" &
            RTSP_SERVER_PID=$!
            BACKGROUND_PIDS+=("$RTSP_SERVER_PID")

            echo -e "\e[33mRTSP server started with PID $RTSP_SERVER_PID\e[0m"
            for mount_point in "${MOUNT_POINTS[@]}"; do
                echo -e "\e[33mStreaming to rtsp://$RTSP_IP:8554${mount_point}\e[0m"
                echo -e "\e[33mStreaming to rtsp://localhost:8554${mount_point}\e[0m"
            done
            ;;
        "separate")
            # Separate servers for external and localhost
            echo -e "\e[33mStarting external RTSP server on port 8554...\e[0m"
            ./multi-stream-server "${SERVER_ARGS[@]}" &
            RTSP_SERVER_PID=$!
            BACKGROUND_PIDS+=("$RTSP_SERVER_PID")

            echo -e "\e[33mExternal RTSP server started with PID $RTSP_SERVER_PID\e[0m"
            for mount_point in "${MOUNT_POINTS[@]}"; do
                echo -e "\e[33mStreaming to rtsp://$RTSP_IP:8554${mount_point}\e[0m"
            done

            # Check if multi-stream-server-port exists
            if [ -f "./multi-stream-server-port" ]; then
                echo -e "\e[33mStarting localhost RTSP server on port 8555...\e[0m"
                ./multi-stream-server-port 8555 "${SERVER_ARGS[@]}" &
                LOCALHOST_SERVER_PID=$!
                BACKGROUND_PIDS+=("$LOCALHOST_SERVER_PID")
                
                echo -e "\e[33mLocalhost RTSP server started with PID $LOCALHOST_SERVER_PID\e[0m"
                for mount_point in "${MOUNT_POINTS[@]}"; do
                    echo -e "\e[33mStreaming to rtsp://localhost:8555${mount_point}\e[0m"
                done
            else
                echo -e "\e[33mCompiling multi-stream-server-port for localhost server...\e[0m"
                gcc -o multi-stream-server-port multi-stream-server-port.c $(pkg-config --cflags --libs gstreamer-rtsp-server-1.0)
                
                if [ -f "./multi-stream-server-port" ]; then
                    echo -e "\e[33mStarting localhost RTSP server on port 8555...\e[0m"
                    ./multi-stream-server-port 8555 "${SERVER_ARGS[@]}" &
                    LOCALHOST_SERVER_PID=$!
                    BACKGROUND_PIDS+=("$LOCALHOST_SERVER_PID")
                    
                    echo -e "\e[33mLocalhost RTSP server started with PID $LOCALHOST_SERVER_PID\e[0m"
                    for mount_point in "${MOUNT_POINTS[@]}"; do
                        echo -e "\e[33mStreaming to rtsp://localhost:8555${mount_point}\e[0m"
                    done
                else
                    echo -e "\e[31mFailed to compile multi-stream-server-port. Using single server.\e[0m"
                    echo -e "\e[33mYou can access streams on localhost:8554 (same as external)\e[0m"
                fi
            fi
            ;;
        "external")
            # External IP only
            echo -e "\e[33mStarting RTSP server with multiple streams...\e[0m"
            ./multi-stream-server "${SERVER_ARGS[@]}" &
            RTSP_SERVER_PID=$!
            BACKGROUND_PIDS+=("$RTSP_SERVER_PID")

            echo -e "\e[33mRTSP server started with PID $RTSP_SERVER_PID\e[0m"
            for mount_point in "${MOUNT_POINTS[@]}"; do
                echo -e "\e[33mStreaming to rtsp://$RTSP_IP:8554${mount_point}\e[0m"
            done
            ;;
    esac

    # Wait for the RTSP server process
    wait $RTSP_SERVER_PID
    exit 0
}


# Function to install gst-rtsp-server and compile multi-stream-server
install_gst_rtsp_server() {
    echo -e "\e[33mInstalling gst-rtsp-server...\e[0m"
    sudo apt-get update
    sudo apt-get install -y libgstrtspserver-1.0-dev gstreamer1.0-rtsp libglib2.0-dev git

    # Download multi-stream-server.c if not present
    if [ ! -f "multi-stream-server.c" ]; then
        echo -e "\e[33mDownloading multi-stream-server.c...\e[0m"
        # Replace the URL with the actual location of your multi-stream-server.c
        wget https://gist.githubusercontent.com/anonymous/abcdef1234567890/raw/multi-stream-server.c
    fi

    # Compile multi-stream-server
    gcc -o multi-stream-server multi-stream-server.c $(pkg-config --cflags --libs gstreamer-rtsp-server-1.0)
    
    # Compile multi-stream-server-port if it exists
    if [ -f "multi-stream-server-port.c" ]; then
        echo -e "\e[33mCompiling multi-stream-server-port...\e[0m"
        gcc -o multi-stream-server-port multi-stream-server-port.c $(pkg-config --cflags --libs gstreamer-rtsp-server-1.0)
    fi
}

# Main script execution starts here

# Print the header
print_header

# Check for required dependencies
echo -e "\e[33mChecking for required dependencies...\e[0m"

# GStreamer
check_install "GStreamer" "gst-launch-1.0" "gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav"

# v4l2-utils for camera
check_install "v4l-utils" "v4l2-ctl" "v4l-utils"

# Tailscale (optional)
TAILSCALE_IP=$(get_tailscale_ip)
if [ -z "$TAILSCALE_IP" ]; then
    echo -e "\e[33mTailscale is not installed or not running.\e[0m"
    read -p "Do you want to install and configure Tailscale? (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo -e "\e[33mInstalling Tailscale...\e[0m"
        curl -fsSL https://tailscale.com/install.sh | sh
        sudo tailscale up
        TAILSCALE_IP=$(get_tailscale_ip)
    else
        echo -e "\e[33mProceeding without Tailscale IP.\e[0m"
    fi
else
    echo -e "\e[32mTailscale is running. IP: $TAILSCALE_IP\e[0m"
fi

# User Interaction
echo -e "\e[33mConfiguring the streaming settings...\e[0m"

# Ask user what they want to stream
echo -e "\e[33mWhat do you want to stream?\e[0m"
echo "1. Cameras"
echo "2. Video Files"
echo "3. Both Cameras and Video Files"
read -p "Enter your choice [1]: " STREAM_CHOICE
STREAM_CHOICE=${STREAM_CHOICE:-1}

while ! [[ "$STREAM_CHOICE" =~ ^[1-3]$ ]]; do
    echo -e "\e[31mInvalid selection. Please enter 1, 2, or 3.\e[0m"
    read -p "Enter your choice [1]: " STREAM_CHOICE
    STREAM_CHOICE=${STREAM_CHOICE:-1}
done

if [ "$STREAM_CHOICE" -eq 1 ] || [ "$STREAM_CHOICE" -eq 3 ]; then
    # List available video devices and classify them
    list_video_devices
    # Select cameras
    select_cameras
fi

if [ "$STREAM_CHOICE" -eq 2 ] || [ "$STREAM_CHOICE" -eq 3 ]; then
    # Select video files
    select_video_files
fi

if [ ${#SELECTED_CAMERAS[@]} -eq 0 ] && [ ${#VIDEO_FILES[@]} -eq 0 ]; then
    echo -e "\e[31mNo cameras or video files selected. Exiting.\e[0m"
    exit 1
fi

# Determine if any USB cameras or video files are selected
USB_CAMERAS_SELECTED=false
STURDECAM_SELECTED=false
if [ ${#SELECTED_CAMERAS[@]} -gt 0 ]; then
    for i in "${!SELECTED_DEVICE_TYPES[@]}"; do
        if [ "${SELECTED_DEVICE_TYPES[$i]}" == "USB Camera" ]; then
            USB_CAMERAS_SELECTED=true
        elif [ "${SELECTED_DEVICE_TYPES[$i]}" == "STURDECAM" ]; then
            STURDECAM_SELECTED=true
        fi
    done
fi

# If STURDECAMs are selected, ask for STURDECAM resolution
if $STURDECAM_SELECTED; then
    select_sturdecam_resolution
fi

# If USB cameras or video files are selected, ask for resolution
if $USB_CAMERAS_SELECTED || [ ${#VIDEO_FILES[@]} -gt 0 ]; then
    # Select resolution
    select_resolution
else
    # Set default resolution for STURDECAMs (if not already set)
    if ! $STURDECAM_SELECTED; then
        WIDTH=1920
        HEIGHT=1536
    fi
fi

# Set streaming protocol to RTSP
select_streaming_protocol

# Install gst-rtsp-server if not installed
if [ ! -f "./multi-stream-server" ]; then
    echo -e "\e[31mgst-rtsp-server or multi-stream-server is not installed.\e[0m"
    read -p "Do you want to install gst-rtsp-server and compile multi-stream-server? (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        install_gst_rtsp_server
    else
        echo -e "\e[31mCannot proceed without gst-rtsp-server. Exiting.\e[0m"
        exit 1
    fi
fi

# Compile multi-stream-server-port if it doesn't exist and we have the source
if [ ! -f "./multi-stream-server-port" ] && [ -f "./multi-stream-server-port.c" ]; then
    echo -e "\e[33mCompiling multi-stream-server-port...\e[0m"
    gcc -o multi-stream-server-port multi-stream-server-port.c $(pkg-config --cflags --libs gstreamer-rtsp-server-1.0)
fi

# Ask for RTSP server IP and localhost option
DEFAULT_IP="${TAILSCALE_IP:-localhost}"
echo -e "\e[33mDefault RTSP server IP: $DEFAULT_IP\e[0m"
read -p "Enter the RTSP server IP [$DEFAULT_IP]: " RTSP_IP
RTSP_IP=${RTSP_IP:-$DEFAULT_IP}

# Ask about localhost streaming options
echo -e "\e[33mLocalhost streaming options:\e[0m"
echo "1. Single server (accessible on both $RTSP_IP and localhost)"
echo "2. Separate servers (external IP on port 8554, localhost on port 8555)"
echo "3. External IP only"
read -p "Enter your choice [1]: " LOCALHOST_CHOICE
LOCALHOST_CHOICE=${LOCALHOST_CHOICE:-1}

case $LOCALHOST_CHOICE in
    1)
        STREAM_TO_LOCALHOST="single"
        echo -e "\e[32mWill use single server accessible on both $RTSP_IP and localhost\e[0m"
        ;;
    2)
        STREAM_TO_LOCALHOST="separate"
        echo -e "\e[32mWill use separate servers: external on port 8554, localhost on port 8555\e[0m"
        ;;
    3)
        STREAM_TO_LOCALHOST="external"
        echo -e "\e[33mWill stream only to external IP $RTSP_IP\e[0m"
        ;;
    *)
        STREAM_TO_LOCALHOST="single"
        echo -e "\e[32mWill use single server accessible on both $RTSP_IP and localhost\e[0m"
        ;;
esac

# Start the GStreamer pipelines
start_gstreamer_pipelines

# The cleanup function will be called automatically due to the trap
