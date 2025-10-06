# RTSP Stream Project Makefile

CC = gcc
CFLAGS = -Wall -Wextra -std=c99
PKG_CONFIG = pkg-config
GSTREAMER_CFLAGS = $(shell $(PKG_CONFIG) --cflags gstreamer-rtsp-server-1.0 gstreamer-rtsp-1.0)
GSTREAMER_LIBS = $(shell $(PKG_CONFIG) --libs gstreamer-rtsp-server-1.0 gstreamer-rtsp-1.0)

# Targets
JETSON_DIR = jetson
ARM_LINUX_DIR = arm-linux

# Jetson binaries
JETSON_TARGETS = $(JETSON_DIR)/multi-stream-server-unified

.PHONY: all clean install check-deps help

all: $(JETSON_TARGETS)

# Build jetson binaries
$(JETSON_DIR)/multi-stream-server-unified: $(JETSON_DIR)/multi-stream-server-unified.c
	$(CC) $(CFLAGS) $(GSTREAMER_CFLAGS) -o $@ $< $(GSTREAMER_LIBS)

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@$(PKG_CONFIG) --exists gstreamer-rtsp-server-1.0 || (echo "Error: gstreamer-rtsp-server-1.0 not found. Please install libgstrtspserver-1.0-dev" && exit 1)
	@echo "All dependencies satisfied."

# Install (copy binaries to system path)
install: $(JETSON_TARGETS)
	@echo "Installing binaries..."
	@sudo cp $(JETSON_TARGETS) /usr/local/bin/
	@echo "Installation complete."

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -f $(JETSON_TARGETS)
	@echo "Clean complete."

# Help
help:
	@echo "Available targets:"
	@echo "  all        - Build all binaries (default)"
	@echo "  clean      - Remove build artifacts"
	@echo "  check-deps - Check if required dependencies are installed"
	@echo "  install    - Install binaries to /usr/local/bin"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Dependencies:"
	@echo "  - libgstrtspserver-1.0-dev (Ubuntu/Debian)"
	@echo "  - gstreamer-rtsp-server-1.0 (runtime)"
