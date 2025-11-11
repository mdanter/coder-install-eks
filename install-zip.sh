#!/bin/sh
set -eu

# Standalone macOS Coder Installation Script
# Usage: ./install-coder-mac.sh /path/to/coder_archive.zip

main() {
 # Check if zip file path was provided
 if [ $# -eq 0 ]; then
  echoerr "Error: No zip file path provided"
  echoerr "Usage: $0 /path/to/coder_archive.zip"
  exit 1
 fi

 ZIP_FILE="$1"

 # Validate the zip file exists
 if [ ! -f "$ZIP_FILE" ]; then
  echoerr "Error: File not found: $ZIP_FILE"
  exit 1
 fi

 # Validate we're on macOS
 OS=$(uname)
 if [ "$OS" != "Darwin" ]; then
  echoerr "Error: This script is for macOS only. Detected OS: $OS"
  exit 1
 fi

 # Set installation defaults
 STANDALONE_INSTALL_PREFIX="${STANDALONE_INSTALL_PREFIX:-$HOME/.local}"
 STANDALONE_BINARY_NAME="${STANDALONE_BINARY_NAME:-coder}"
 CACHE_DIR="${CACHE_DIR:-$HOME/.cache/coder}"

 echoh "Installing Coder from local zip file: $ZIP_FILE"
 echoh

 # Create cache directory for extraction
 sh_c mkdir -p "$CACHE_DIR/tmp"

 # Extract the zip file
 echoh "Extracting archive..."
 sh_c unzip -d "$CACHE_DIR/tmp" -o "$ZIP_FILE"

 STANDALONE_BINARY_LOCATION="$STANDALONE_INSTALL_PREFIX/bin/$STANDALONE_BINARY_NAME"

 # Determine if we need sudo
 sh_c="sh_c"
 if [ ! -w "$STANDALONE_INSTALL_PREFIX" ]; then
  echoh "Installation directory requires elevated privileges"
  sh_c="sudo_sh_c"
 fi

 # Create installation directory
 "$sh_c" mkdir -p "$STANDALONE_INSTALL_PREFIX/bin"

 # Remove existing binary if present
 if [ -f "$STANDALONE_BINARY_LOCATION" ]; then
  echoh "Removing existing installation..."
  "$sh_c" rm "$STANDALONE_BINARY_LOCATION"
 fi

 # Copy the binary to the installation location
 echoh "Installing binary to $STANDALONE_BINARY_LOCATION"
 "$sh_c" cp "$CACHE_DIR/tmp/coder" "$STANDALONE_BINARY_LOCATION"

 # Make it executable
 "$sh_c" chmod +x "$STANDALONE_BINARY_LOCATION"

 # Clean up extracted files
 echoh "Cleaning up temporary files..."
 sh_c rm -rf "$CACHE_DIR/tmp"

 echo_postinstall
}

# Helper functions
echoh() {
 echo "$@"
}

echoerr() {
 echo "$@" >&2
}

sh_c() {
 echoh "+ $*"
 sh -c "$*"
}

sudo_sh_c() {
 if [ "$(id -u)" = 0 ]; then
  sh_c "$@"
 else
  echoh "+ sudo $*"
  sudo sh -c "$*"
 fi
}

echo_postinstall() {
 cat <<EOF

✓ Coder installation complete!

The Coder binary has been installed to:
  $STANDALONE_BINARY_LOCATION

EOF

 CODER_COMMAND="$(command -v "$STANDALONE_BINARY_NAME" 2>/dev/null || true)"

 if [ -z "$CODER_COMMAND" ]; then
  cat <<EOF
To use Coder, add it to your PATH:

  export PATH="$STANDALONE_INSTALL_PREFIX/bin:\$PATH"

Add this to your ~/.zshrc or ~/.bash_profile to make it permanent.

EOF
 elif [ "$CODER_COMMAND" != "$STANDALONE_BINARY_LOCATION" ]; then
  cat <<EOF
⚠ Warning: Another coder installation was found at:
  $CODER_COMMAND

This may conflict with the newly installed version at:
  $STANDALONE_BINARY_LOCATION

Consider removing the old installation or adjusting your PATH.

EOF
 else
  cat <<EOF
To run a Coder server:
  $ $STANDALONE_BINARY_NAME server

To connect to a Coder deployment:
  $ $STANDALONE_BINARY_NAME login <deployment-url>

EOF
 fi
}

main "$@"
