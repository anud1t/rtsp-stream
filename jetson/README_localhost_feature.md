# Localhost Streaming Feature

## Overview

The RTSP streaming script now includes enhanced localhost streaming options that allow you to configure how your streams are accessible on the local machine.

## New Features

### 1. Single Server Mode (Default)
- **Description**: One RTSP server accessible on both external IP and localhost
- **Port**: 8554
- **Access URLs**: 
  - `rtsp://EXTERNAL_IP:8554/stream_name`
  - `rtsp://localhost:8554/stream_name`
- **Use Case**: When you want the same server to be accessible both locally and remotely

### 2. Separate Servers Mode
- **Description**: Two separate RTSP servers - one for external access, one for localhost
- **Ports**: 
  - External: 8554
  - Localhost: 8555
- **Access URLs**:
  - External: `rtsp://EXTERNAL_IP:8554/stream_name`
  - Localhost: `rtsp://localhost:8555/stream_name`
- **Use Case**: When you want to isolate local and remote access, or need different configurations

### 3. External Only Mode
- **Description**: RTSP server accessible only via external IP
- **Port**: 8554
- **Access URL**: `rtsp://EXTERNAL_IP:8554/stream_name`
- **Use Case**: When you only need remote access and want to restrict local access

## How to Use

1. Run the streaming script:
   ```bash
   ./rtsp_stream.sh
   ```

2. Follow the prompts to select your streaming sources (cameras, video files, or both)

3. When prompted for localhost options, choose:
   - `1` for Single Server Mode
   - `2` for Separate Servers Mode  
   - `3` for External Only Mode

## Technical Details

### New Binary: multi-stream-server-port
A new version of the multi-stream-server has been created that accepts a port parameter:

```bash
./multi-stream-server-port [port] [mount_point pipeline_description]...
```

**Examples:**
```bash
# Server on port 8554 (default)
./multi-stream-server-port 8554 /cam1 "( v4l2src device=/dev/video0 ! ... )"

# Server on port 8555
./multi-stream-server-port 8555 /cam1 "( v4l2src device=/dev/video0 ! ... )"
```

### Automatic Compilation
The script automatically compiles `multi-stream-server-port` if the source file exists and the binary is missing.

## Benefits

1. **Flexibility**: Choose the access pattern that best fits your use case
2. **Security**: Option to restrict local access if needed
3. **Isolation**: Separate servers for different access patterns
4. **Compatibility**: Maintains backward compatibility with existing setups

## Troubleshooting

### Port Already in Use
If you get a "port already in use" error:
1. Check if another RTSP server is running: `netstat -tulpn | grep 8554`
2. Kill the existing process or choose a different port

### Compilation Issues
If `multi-stream-server-port` fails to compile:
1. Ensure gst-rtsp-server development packages are installed
2. Check that `multi-stream-server-port.c` exists in the directory
3. The script will fall back to single server mode

### Access Issues
- Verify firewall settings allow access to the chosen ports
- For separate servers mode, ensure both ports (8554 and 8555) are accessible
- Test localhost access with: `ffplay rtsp://localhost:8554/stream_name` 