
# RTSP Stream Script

**RTSP Stream Script** is a Bash script designed to stream multiple cameras and video files over RTSP using GStreamer and `gst-rtsp-server`. It provides an interactive setup to configure various streaming parameters, ensuring a seamless streaming experience for multiple sources simultaneously.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Streaming Protocol](#streaming-protocol)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- **Multiple Stream Support**: Stream up to 4 cameras and 4 video files concurrently.
- **Encoder Selection**: Choose from available hardware-accelerated or software encoders.
- **Resolution Configuration**: Select predefined resolutions or set custom dimensions.
- **Tailscale Integration**: Optionally configure Tailscale for secure remote access.
- **Automatic Dependency Management**: Checks and installs necessary dependencies.
- **Graceful Cleanup**: Ensures all background processes are terminated upon exit.

## Prerequisites

Before using the script, ensure your system meets the following requirements:

- **Operating System**: Debian-based Linux distributions (e.g., Ubuntu).
- **User Permissions**: Sudo privileges for installing packages and configuring system settings.
- **Hardware**: Up to 4 USB or built-in cameras supported by `v4l2`.

## Installation

1. **Clone the Repository**

   ```bash
   git clone https://github.com/anudit/multi-rtsp-stream.git
   cd rtsp-stream
   ```

2. **Ensure Script is Executable**

   ```bash
   chmod +x multi_rtsp_stream.sh
   ```

3. **Prepare `multi-stream-server`**

   The script relies on `multi-stream-server`, which needs to be compiled from source.

   ```bash
   gcc -o multi-stream-server multi-stream-server.c $(pkg-config --cflags --libs gstreamer-rtsp-server-1.0)
   ```

   > **Note**: The script can automatically handle this step if `multi-stream-server` is not found. However, having the C source file (`multi-stream-server.c`) in the same directory is essential.

## Usage

Run the script using Bash:

```bash
./multi_rtsp_stream.sh
```

The script will guide you through an interactive setup process:

1. **Dependency Check**: Ensures all necessary packages are installed. Offers to install missing dependencies.
2. **Encoder Selection**: Lists available GStreamer encoders and prompts you to choose one.
3. **Resolution Selection**: Choose from predefined resolutions or set a custom resolution.
4. **Streaming Source Selection**:
   - **Cameras**: Select up to 4 connected video devices.
   - **Video Files**: Provide paths to up to 4 video files for streaming.
5. **Tailscale Configuration**: Optionally install and configure Tailscale for remote access.
6. **RTSP Server Setup**: Configures and starts the RTSP server with the selected streams.

## Configuration

### Resolution Configuration

Select from common resolutions:

- 1920x1080
- 1280x720
- 640x480
- Custom (specify width and height)

### Stream Naming

For each selected video file and camera, you can assign a custom stream name, which determines the RTSP endpoint (e.g., `rtsp://<IP>:8554/<stream_name>`).

### Tailscale Integration

If you opt to use Tailscale, the script will:

1. Install Tailscale if not already present.
2. Configure it to obtain a Tailscale IP for secure remote access.

## Streaming Protocol

The script is configured to use the **RTSP (Real Time Streaming Protocol)**. Streams are accessible via URLs in the format:

```
rtsp://<RTSP_IP>:8554/<stream_name>
```

- **RTSP_IP**: Default is `localhost` or your Tailscale IP if configured.
- **Port**: 8554 (default for RTSP servers).
- **Stream Name**: Defined during the configuration step.

## Troubleshooting

- **No Video Devices Found**: Ensure cameras are connected and recognized by the system. Use `v4l2-ctl --list-devices` to verify.
- **Dependency Installation Issues**: Check your internet connection and package manager settings. Ensure you have sudo privileges.
- **`multi-stream-server` Compilation Errors**: Verify that `libgstrtspserver-1.0-dev` and other development packages are installed.
- **RTSP Server Not Accessible**: Ensure firewall settings allow traffic on port 8554. Verify the RTSP IP address.

## License

This project is licensed under the [MIT License](LICENSE).

---