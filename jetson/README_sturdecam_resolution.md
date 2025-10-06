# STURDECAM Resolution Feature

## Overview

The RTSP streaming script now includes configurable resolution options for STURDECAM devices, allowing you to choose between native resolution, standard HD resolutions, or custom resolutions.

## New Features

### STURDECAM Resolution Options

1. **1920x1536 (Native)** - Default STURDECAM resolution
   - Best quality output
   - Higher bandwidth usage
   - Native sensor resolution

2. **1920x1080 (1080p)** - Standard Full HD
   - Standard 1080p resolution
   - Good balance of quality and bandwidth
   - Compatible with most displays

3. **1280x720 (720p)** - Standard HD
   - Lower bandwidth usage
   - Faster streaming
   - Good for network-constrained environments

4. **Custom** - User-defined resolution
   - Enter custom width and height
   - Tailored to specific requirements
   - Maximum flexibility

## How to Use

1. Run the streaming script:
   ```bash
   ./rtsp_stream.sh
   ```

2. Select cameras as your streaming source

3. Choose your STURDECAM device(s)

4. When prompted for STURDECAM resolution, select your preferred option:
   - `1` for Native (1920x1536)
   - `2` for 1080p (1920x1080)
   - `3` for 720p (1280x720)
   - `4` for Custom resolution

## Technical Details

### Pipeline Configuration

The STURDECAM pipeline automatically adjusts based on your resolution choice:

```bash
# Example pipeline for 1080p
v4l2src device=/dev/video0 ! video/x-raw,width=1920,height=1080,format=UYVY ! \
videoconvert ! nvvidconv ! video/x-raw(memory:NVMM),format=I420 ! \
nvv4l2h264enc bitrate=10000000 ! h264parse ! rtph264pay config-interval=1 pt=96
```

### Hardware Acceleration

All STURDECAM resolutions use NVIDIA hardware acceleration:
- **nvvidconv**: Hardware video conversion
- **nvv4l2h264enc**: Hardware H.264 encoding
- **Optimized for Jetson platforms**

### Bandwidth Considerations

| Resolution | Approximate Bitrate | Use Case |
|------------|-------------------|----------|
| 1920x1536 (Native) | ~15-20 Mbps | High-quality applications |
| 1920x1080 (1080p) | ~8-12 Mbps | Standard HD streaming |
| 1280x720 (720p) | ~4-6 Mbps | Bandwidth-constrained networks |
| Custom | Variable | Specific requirements |

## Benefits

1. **Flexibility**: Choose the resolution that best fits your use case
2. **Bandwidth Optimization**: Lower resolutions for network-constrained environments
3. **Quality Control**: Higher resolutions for applications requiring maximum quality
4. **Compatibility**: Standard resolutions work with most displays and players
5. **Hardware Optimization**: All resolutions leverage NVIDIA hardware acceleration

## Example Usage

### 1080p Streaming
```bash
./rtsp_stream.sh
# Select: Cameras
# Select: STURDECAM device
# Select: Resolution option 2 (1080p)
# Result: Streams at 1920x1080 via RTSP
```

### Custom Resolution
```bash
./rtsp_stream.sh
# Select: Cameras  
# Select: STURDECAM device
# Select: Resolution option 4 (Custom)
# Enter: Width = 1600, Height = 900
# Result: Streams at 1600x900 via RTSP
```

## Troubleshooting

### Resolution Not Applied
- Ensure you selected a STURDECAM device
- Check that the resolution selection was completed
- Verify the pipeline output shows the correct resolution

### Performance Issues
- Lower resolutions may improve performance on slower networks
- Higher resolutions require more processing power
- Monitor system resources during streaming

### Compatibility Issues
- Some players may not support non-standard resolutions
- Use standard resolutions (720p, 1080p) for maximum compatibility
- Test with your target playback application

## Integration with Localhost Feature

The STURDECAM resolution feature works seamlessly with the localhost streaming options:

- **Single Server**: Same resolution on both external and localhost
- **Separate Servers**: Same resolution on both ports (8554 and 8555)
- **External Only**: Resolution applied to external streaming only

All resolution options are applied consistently across your chosen localhost configuration. 