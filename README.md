# RTSP Stream System

A comprehensive RTSP streaming solution for multiple cameras and video files using GStreamer and gst-rtsp-server. Supports both Jetson and ARM Linux platforms with hardware acceleration and flexible configuration options.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Advanced Features](#advanced-features)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- **Multiple Stream Support**: Stream up to 4 cameras and 4 video files concurrently
- **Hardware Acceleration**: NVIDIA Jetson hardware acceleration for STURDECAM devices
- **Flexible Resolution Options**: Native, standard HD, or custom resolutions
- **Dual Server Support**: Separate servers for external and localhost access
- **Tailscale Integration**: Optional secure remote access via Tailscale
- **Automatic Dependency Management**: Checks and installs necessary dependencies
- **Graceful Cleanup**: Ensures all background processes are terminated on exit
- **Unified Interface**: Single script handles all streaming scenarios

## Prerequisites

- **Operating System**: Debian-based Linux distributions (Ubuntu, etc.)
- **User Permissions**: Sudo privileges for installing packages
- **Hardware**: Up to 4 USB or built-in cameras supported by `v4l2`
- **For Jetson**: NVIDIA Jetson platform for hardware acceleration

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/rtsp-stream.git
cd rtsp-stream
```

### 2. Build the Project

```bash
make all
```

This will compile the unified RTSP server binary.

### 3. Install Dependencies (if needed)

The script will automatically check and offer to install missing dependencies:

- GStreamer and plugins
- v4l-utils for camera support
- gst-rtsp-server development packages

## Usage

### Basic Usage

Run the main streaming script:

```bash
./rtsp-stream.sh
```

The script will guide you through an interactive setup:

1. **Dependency Check**: Ensures all necessary packages are installed
2. **Source Selection**: Choose cameras, video files, or both
3. **Device Selection**: Select up to 4 cameras or video files
4. **Resolution Configuration**: Choose output resolution
5. **Server Configuration**: Configure RTSP server options
6. **Streaming**: Start the RTSP streams

### Command Line Options

The unified RTSP server supports flexible port configuration:

```bash
# Default port (8554)
./jetson/multi-stream-server-unified /cam1 "( v4l2src device=/dev/video0 ! ... )"

# Custom port
./jetson/multi-stream-server-unified --port 8555 /cam1 "( v4l2src device=/dev/video0 ! ... )"
```

## Configuration

### Resolution Options

#### Standard Resolutions
- **1920x1080 (1080p)**: Full HD quality
- **1280x720 (720p)**: HD quality, lower bandwidth
- **640x480 (480p)**: Lower quality, minimal bandwidth
- **Custom**: User-defined width and height

#### STURDECAM Resolutions
- **1920x1536 (Native)**: Best quality, higher bandwidth
- **1920x1080 (1080p)**: Standard HD, good balance
- **1280x720 (720p)**: Lower bandwidth, faster streaming
- **Custom**: Tailored to specific requirements

### Streaming Modes

#### 1. Single Server Mode (Default)
- **Description**: One RTSP server accessible on both external IP and localhost
- **Port**: 8554
- **Access URLs**: 
  - `rtsp://EXTERNAL_IP:8554/stream_name`
  - `rtsp://localhost:8554/stream_name`
- **Use Case**: When you want the same server accessible both locally and remotely

#### 2. Separate Servers Mode
- **Description**: Two separate RTSP servers - one for external access, one for localhost
- **Ports**: 
  - External: 8554
  - Localhost: 8555
- **Access URLs**:
  - External: `rtsp://EXTERNAL_IP:8554/stream_name`
  - Localhost: `rtsp://localhost:8555/stream_name`
- **Use Case**: When you want to isolate local and remote access

#### 3. External Only Mode
- **Description**: RTSP server accessible only via external IP
- **Port**: 8554
- **Access URL**: `rtsp://EXTERNAL_IP:8554/stream_name`
- **Use Case**: When you only need remote access

## Advanced Features

### Hardware Acceleration

The system automatically detects and uses hardware acceleration when available:

- **NVIDIA Jetson**: Uses `nvvidconv` and `nvv4l2h264enc` for hardware encoding
- **STURDECAM Devices**: Optimized pipelines for STURDECAM hardware
- **USB Cameras**: Software encoding with `x264enc`

### Device Detection

The script automatically detects and classifies video devices:

- **STURDECAM**: NVIDIA Jetson-specific cameras with hardware acceleration
- **USB Cameras**: Standard USB video devices with software encoding

### Tailscale Integration

Optional secure remote access:

1. Install Tailscale if not present
2. Configure for secure remote access
3. Streams accessible via Tailscale IP

## Troubleshooting

### Common Issues

#### No Video Devices Found
- Ensure cameras are connected and recognized
- Use `v4l2-ctl --list-devices` to verify
- Check user permissions (add to `video` group)

#### Dependency Installation Issues
- Check internet connection and package manager settings
- Ensure sudo privileges are available
- Verify package repository configuration

#### Compilation Errors
- Install development packages: `libgstrtspserver-1.0-dev`
- Check GStreamer installation
- Verify build tools are available

#### RTSP Server Not Accessible
- Check firewall settings for port 8554/8555
- Verify RTSP IP address configuration
- Test with: `ffplay rtsp://localhost:8554/stream_name`

#### Port Already in Use
- Check for existing RTSP servers: `netstat -tulpn | grep 8554`
- Kill existing processes or choose different ports
- Use `--port` option for custom ports

### Performance Optimization

#### Bandwidth Considerations

| Resolution | Approximate Bitrate | Use Case |
|------------|-------------------|----------|
| 1920x1536 (Native) | ~15-20 Mbps | High-quality applications |
| 1920x1080 (1080p) | ~8-12 Mbps | Standard HD streaming |
| 1280x720 (720p) | ~4-6 Mbps | Bandwidth-constrained networks |
| Custom | Variable | Specific requirements |

#### Hardware Acceleration
- Use STURDECAM devices for best performance on Jetson
- Lower resolutions for network-constrained environments
- Monitor system resources during streaming

## Project Structure

```
rtsp-stream/
├── rtsp-stream.sh              # Main streaming script
├── common.sh                   # Shared functions library
├── Makefile                    # Build system
├── .gitignore                  # Git ignore patterns
├── .editorconfig               # Code formatting rules
├── jetson/                     # Jetson-specific code
│   ├── multi-stream-server-unified.c  # Unified RTSP server
│   └── multi-stream-server-unified    # Compiled binary
└── arm-linux/                  # ARM Linux scripts (legacy)
    └── rtsp_universal.sh       # Legacy universal script
```

## Development

### Building from Source

```bash
# Build all targets
make all

# Check dependencies
make check-deps

# Clean build artifacts
make clean

# Install to system
make install

# Show help
make help
```

### Code Style

The project uses `.editorconfig` for consistent formatting:
- C files: 4 spaces, LF line endings
- Shell scripts: 2 spaces, LF line endings
- Markdown: No trailing whitespace

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
1. Check the troubleshooting section
2. Search existing issues
3. Create a new issue with detailed information

---

**Note**: This project has been cleaned up and consolidated from multiple redundant scripts into a unified, maintainable solution. The old separate scripts are preserved in the `jetson/` and `arm-linux/` directories for reference but are no longer actively maintained.