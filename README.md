# RTSP Stream System

A simple RTSP streaming solution for multiple cameras and video files using GStreamer.

## Quick Start

1. **Clone and build:**
   ```bash
   git clone https://github.com/yourusername/rtsp-stream.git
   cd rtsp-stream
   make all
   ```

2. **Run the streaming script:**
   ```bash
   ./rtsp-stream.sh
   ```

3. **Follow the prompts to select cameras and configure streaming**

## Features

- Stream up to 4 cameras and 4 video files simultaneously
- Hardware acceleration for NVIDIA Jetson devices
- Multiple resolution options (720p, 1080p, custom)
- Flexible server configuration (single or separate servers)
- Automatic dependency installation

## Requirements

- Ubuntu/Debian Linux
- GStreamer and gst-rtsp-server
- v4l-utils for camera support
- Sudo privileges for package installation

## Installation

The script will automatically check and install missing dependencies when you run it.

For manual installation:
```bash
sudo apt-get update
sudo apt-get install -y gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav libgstrtspserver-1.0-dev v4l-utils
```

## Usage

### Basic Usage
```bash
./rtsp-stream.sh
```

### Manual RTSP Server
```bash
# Default port (8554)
./jetson/multi-stream-server-unified /cam1 "( v4l2src device=/dev/video0 ! ... )"

# Custom port
./jetson/multi-stream-server-unified --port 8555 /cam1 "( v4l2src device=/dev/video0 ! ... )"
```

## Configuration

### Resolution Options
- 1920x1080 (1080p)
- 1280x720 (720p) - Default
- 640x480 (480p)
- Custom resolution

### Streaming Modes
1. **Single Server**: One server accessible on both external IP and localhost (port 8554)
2. **Separate Servers**: External server on port 8554, localhost server on port 8555
3. **External Only**: Server accessible only via external IP (port 8554)

## Building

```bash
# Build all binaries
make all

# Check dependencies
make check-deps

# Clean build artifacts
make clean

# Install to system
make install
```

## Troubleshooting

### No cameras detected
- Ensure cameras are connected and recognized
- Check with: `v4l2-ctl --list-devices`
- Verify user permissions (add to video group)

### Dependencies missing
- Run: `make check-deps`
- Install manually: `sudo apt-get install libgstrtspserver-1.0-dev`

### Port already in use
- Check: `netstat -tulpn | grep 8554`
- Kill existing processes or use different port

### RTSP server not accessible
- Check firewall settings
- Verify IP address configuration
- Test with: `ffplay rtsp://localhost:8554/stream_name`

## Project Structure

```
rtsp-stream/
├── rtsp-stream.sh              # Main streaming script
├── common.sh                   # Shared functions
├── Makefile                    # Build system
├── README.md                   # This file
└── jetson/                     # Jetson-specific code
    ├── multi-stream-server-unified.c  # RTSP server source
    └── multi-stream-server-unified    # Compiled binary
```

## License

MIT License

## Support

For issues and questions, please check the troubleshooting section above or create an issue on GitHub.