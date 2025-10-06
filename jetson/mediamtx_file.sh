#!/usr/bin/env bash
###############################################################################
# A Script to Setup and Run up to 4 RTSP Streams via MediaMTX on Linux (AMD/ARM)
# - Streams video files in a loop
# - Uses Tailscale IP if available (fallback: localhost)
# - Allows user to pick CPU/GPU acceleration
# - Allows resolution choice or custom
# - Auto-downloads MediaMTX for AMD64 or ARM if not present
# - Kills all processes gracefully on Ctrl+C
###############################################################################

# --- COLORS / STYLES FOR TERMINAL UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
RESET='\033[0m'

# --- GLOBAL VARIABLES ---
MEDIAMTX_BIN="/usr/local/bin/mediamtx"
MEDIAMTX_CONFIG="/tmp/mediamtx.yml"
FFMPEG_PROCESSES=()   # track ffmpeg pids
MEDIAMTX_PROCESS=""
NUM_STREAMS=0
declare -a VIDEO_FILES
declare -a RTSP_PATHS

###############################################################################
# Function: Cleanup on Ctrl+C
###############################################################################
cleanup() {
  echo -e "\n${RED}[*] Caught Ctrl+C! Stopping streams and MediaMTX...${RESET}"

  # Kill all ffmpeg processes
  for pid in "${FFMPEG_PROCESSES[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
    fi
  done

  # Kill MediaMTX
  if [[ -n "${MEDIAMTX_PROCESS}" ]]; then
    if kill -0 "${MEDIAMTX_PROCESS}" 2>/dev/null; then
      kill "${MEDIAMTX_PROCESS}"
    fi
  fi

  sleep 1
  exit 0
}
trap cleanup INT

###############################################################################
# Print Banner
###############################################################################
echo -e "${MAGENTA}"
cat << "EOF"
  __  __          _     __  __ _____  __  __
 |  \/  |   /\   | |   |  \/  |  __ \|  \/  |
 | \  / |  /  \  | |   | \  / | |__) | \  / |
 | |\/| | / /\ \ | |   | |\/| |  ___/| |\/| |
 | |  | |/ ____ \| |___| |  | | |    | |  | |
 |_|  |_/_/    \_\_____|_|  |_|_|    |_|  |_|

EOF
echo -e "${CYAN}${BOLD}Welcome to the RTSP Setup Script using MediaMTX!${RESET}\n"

###############################################################################
# Check Dependencies
###############################################################################
check_dependencies() {
  local DEPS=("curl" "ffmpeg")
  for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      echo -e "${YELLOW}[!] '$dep' not found. Attempting to install...${RESET}"
      if [[ -f /etc/debian_version ]]; then
        sudo apt-get update && sudo apt-get install -y "$dep"
      else
        echo -e "${RED}[-] Please install '$dep' manually and re-run the script.${RESET}"
        exit 1
      fi
    fi
  done
}
check_dependencies

###############################################################################
# Detect Tailscale IP
###############################################################################
detect_tailscale_ip() {
  local TS_IP=""
  if command -v tailscale &>/dev/null; then
    # pick the first IPv4 address
    TS_IP=$(tailscale ip -4 | head -n 1)
  fi
  if [[ -z "$TS_IP" ]]; then
    TS_IP="127.0.0.1"
  fi
  echo "$TS_IP"
}

###############################################################################
# Install MediaMTX if needed
###############################################################################
install_mediamtx() {
  if [[ -x "$MEDIAMTX_BIN" ]]; then
    echo -e "${GREEN}[✓] MediaMTX already installed at $MEDIAMTX_BIN${RESET}"
    return
  fi

  local ARCH
  ARCH=$(uname -m)
  local DOWNLOAD_URL=""
  local VERSION="v0.22.3"  # Adjust version as needed

  echo -e "${CYAN}[i] Downloading MediaMTX for architecture: ${ARCH}${RESET}"
  case "$ARCH" in
    x86_64|amd64)
      DOWNLOAD_URL="https://github.com/bluenviron/mediamtx/releases/download/${VERSION}/mediamtx_linux_amd64.tar.gz"
      ;;
    aarch64|arm64)
      DOWNLOAD_URL="https://github.com/bluenviron/mediamtx/releases/download/${VERSION}/mediamtx_linux_arm64.tar.gz"
      ;;
    armv7l)
      DOWNLOAD_URL="https://github.com/bluenviron/mediamtx/releases/download/${VERSION}/mediamtx_linux_armv7.tar.gz"
      ;;
    *)
      echo -e "${RED}[-] Unsupported architecture: $ARCH. Exiting.${RESET}"
      exit 1
      ;;
  esac

  mkdir -p /tmp/mediamtx_install
  cd /tmp/mediamtx_install || exit 1
  curl -L -o mediamtx.tar.gz "$DOWNLOAD_URL"
  tar xzf mediamtx.tar.gz
  sudo mv mediamtx "$MEDIAMTX_BIN"
  sudo chmod +x "$MEDIAMTX_BIN"
  cd - || exit 1
  rm -rf /tmp/mediamtx_install

  if [[ ! -x "$MEDIAMTX_BIN" ]]; then
    echo -e "${RED}[-] MediaMTX installation failed!${RESET}"
    exit 1
  fi
  echo -e "${GREEN}[✓] MediaMTX installed successfully.${RESET}"
}

install_mediamtx

###############################################################################
# Prompt for GPU or CPU Acceleration
###############################################################################
choose_acceleration() {
  # Check if nvidia-smi or vainfo is present
  local GPU_AVAILABLE="no"
  if command -v nvidia-smi &>/dev/null || command -v vainfo &>/dev/null; then
    GPU_AVAILABLE="yes"
  fi

  if [[ "$GPU_AVAILABLE" == "yes" ]]; then
    echo -e "${CYAN}GPU acceleration seems to be available on this system.${RESET}"
    read -rp "Would you like to use GPU acceleration? (yes/no): " USE_GPU
    if [[ "$USE_GPU" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo "GPU"
    else
      echo "CPU"
    fi
  else
    echo -e "${YELLOW}No GPU acceleration detected; using CPU.${RESET}"
    echo "CPU"
  fi
}

###############################################################################
# Build FFMPEG arguments based on chosen acceleration
###############################################################################
build_ffmpeg_args() {
  local method="$1"
  local ffargs=""
  # Extend these if you want to actually leverage GPU encoders:
  if [[ "$method" == "GPU" ]]; then
    # For example, NVIDIA GPU:
    # ffargs="-hwaccel cuda -hwaccel_output_format cuda -c:v h264_nvenc"
    # Or for VAAPI:
    # ffargs="-hwaccel vaapi -hwaccel_output_format vaapi -vf 'format=nv12|vaapi,hwupload' -c:v h264_vaapi"
    #
    # By default, we'll keep them empty so it doesn't fail if drivers are missing.
    ffargs=""
  else
    ffargs=""
  fi
  echo "$ffargs"
}

###############################################################################
# Main Script Flow
###############################################################################

TAILSCALE_IP=$(detect_tailscale_ip)
echo -e "${GREEN}[✓] Using Tailscale/Local IP: $TAILSCALE_IP${RESET}"

# Ask user how many streams (1-4)
while true; do
  read -rp "How many RTSP streams do you want to create? (1-4): " NUM_STREAMS
  if [[ "$NUM_STREAMS" =~ ^[1-4]$ ]]; then
    break
  else
    echo -e "${YELLOW}Please enter a valid number between 1 and 4.${RESET}"
  fi
done

# Gather inputs for each stream
for ((i=1; i<=NUM_STREAMS; i++)); do
  echo -e "\n${CYAN}--- Stream #$i ---${RESET}"
  read -rp "  Enter path to video file: " VIDEO_FILES[$i]
  while [[ ! -f "${VIDEO_FILES[$i]}" ]]; do
    echo -e "${RED}  [!] File not found. Please enter a valid path.${RESET}"
    read -rp "  Enter path to video file: " VIDEO_FILES[$i]
  done

  read -rp "  Enter RTSP suffix name (default: 'video$i'): " RTSP_PATHS[$i]
  if [[ -z "${RTSP_PATHS[$i]}" ]]; then
    RTSP_PATHS[$i]="video$i"
  fi
done

# Resolution selection
echo -e "\n${CYAN}--- Resolution Options (scaling) ---${RESET}"
echo "1) 1080p (1920x1080)"
echo "2) 720p  (1280x720)"
echo "3) 480p  (854x480)"
echo "4) Custom"
read -rp "Select an option (1/2/3/4): " RES_CHOICE

case "$RES_CHOICE" in
  1)
    WIDTH=1920
    HEIGHT=1080
    ;;
  2)
    WIDTH=1280
    HEIGHT=720
    ;;
  3)
    WIDTH=854
    HEIGHT=480
    ;;
  4)
    read -rp "Enter custom width: " WIDTH
    read -rp "Enter custom height: " HEIGHT
    ;;
  *)
    echo -e "${RED}Invalid choice. Defaulting to 720p.${RESET}"
    WIDTH=1280
    HEIGHT=720
    ;;
esac
echo -e "${GREEN}[✓] Selected resolution: ${WIDTH}x${HEIGHT}${RESET}\n"

# GPU or CPU choice
ACCEL_CHOICE=$(choose_acceleration)
FFMPEG_HWACCEL_ARGS=$(build_ffmpeg_args "$ACCEL_CHOICE")
echo -e "${GREEN}[✓] Using $ACCEL_CHOICE acceleration${RESET}"

###############################################################################
# Generate MediaMTX Configuration
###############################################################################
# We'll create a minimal config that matches the default style:
#
# logLevel: info
# rtsp: yes
# rtspAddress: :8554
# protocols: [udp, multicast, tcp]
# paths: ...
#
generate_mediamtx_config() {
  cat <<EOF > "$MEDIAMTX_CONFIG"
# Minimal valid config for current MediaMTX (matching default style)
logLevel: info

################################################################################
# RTSP server
################################################################################
rtsp: yes
rtspAddress: :8554
protocols: [udp, multicast, tcp]
encryption: "no"

################################################################################
# RTMP server
################################################################################
rtmp: yes
rtmpAddress: :1935
rtmpEncryption: "no"

################################################################################
# HLS server
################################################################################
hls: yes
hlsAddress: :8888
hlsEncryption: no

################################################################################
# WebRTC server
################################################################################
webrtc: yes
webrtcAddress: :8889
webrtcEncryption: no

################################################################################
# SRT server
################################################################################
srt: yes
srtAddress: :8890

################################################################################
# Paths definition
################################################################################
paths:
EOF

  for ((i=1; i<=NUM_STREAMS; i++)); do
    local path_name="${RTSP_PATHS[$i]}"
    cat <<EOF >> "$MEDIAMTX_CONFIG"
  $path_name:
    # This path accepts an incoming RTSP/RTMP/SRT/WebRTC publish from ffmpeg.
    source: publisher
EOF
  done

  # A fallback entry for "all other" paths, if desired:
  cat <<EOF >> "$MEDIAMTX_CONFIG"
  all_others:
    source: publisher
EOF
}

generate_mediamtx_config

###############################################################################
# Start MediaMTX in background
###############################################################################
echo -e "${CYAN}[i] Starting MediaMTX server with config: $MEDIAMTX_CONFIG${RESET}"
"$MEDIAMTX_BIN" "$MEDIAMTX_CONFIG" &
MEDIAMTX_PROCESS=$!
# Wait a second for server to init
sleep 1

###############################################################################
# Start FFMPEG processes for each stream
###############################################################################
echo -e "${CYAN}[i] Starting ffmpeg loops for each video...${RESET}"
for ((i=1; i<=NUM_STREAMS; i++)); do
  FILE="${VIDEO_FILES[$i]}"
  RTSP_NAME="${RTSP_PATHS[$i]}"

  echo -e "  -> Stream #$i => file: $FILE, path: rtsp://$TAILSCALE_IP:8554/$RTSP_NAME"

  ffmpeg -re \
    -stream_loop -1 \
    $FFMPEG_HWACCEL_ARGS \
    -i "$FILE" \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease" \
    -c:v libx264 -preset veryfast -tune zerolatency -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -f rtsp "rtsp://$TAILSCALE_IP:8554/$RTSP_NAME" &>/dev/null &

  FFMPEG_PROCESSES+=("$!")
done

###############################################################################
# Final Summary
###############################################################################
echo -e "\n${GREEN}${BOLD}All set! The following RTSP streams should be live:${RESET}"
for ((i=1; i<=NUM_STREAMS; i++)); do
  echo -e "  ${CYAN}rtsp://${TAILSCALE_IP}:8554/${RTSP_PATHS[$i]}${RESET}"
done

echo -e "\n${YELLOW}Press Ctrl+C to stop all streams and MediaMTX.${RESET}"

# Keep the script running until Ctrl+C
wait
