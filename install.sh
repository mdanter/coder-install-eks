#!/bin/bash
set -e

# Coder CLI Installer for macOS (Airgapped)
# Downloads from your Coder deployment's /bin endpoint

VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_debug() { [ "$DEBUG" = "1" ] && echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Defaults
INSTALL_DIR=""
SKIP_VERIFY=0
DEBUG=0
AUTO_PATH=0
INSECURE=0

usage() {
    cat << EOF
Coder CLI Installer for macOS (Airgapped) - v${VERSION}

Usage: $0 [OPTIONS] <coder-url>

OPTIONS:
    -d, --dir <path>        Installation directory (default: /usr/local/bin)
    -s, --skip-verify       Skip binary verification
    -k, --insecure          Allow insecure HTTPS (skip cert validation)
    -p, --auto-path         Automatically add to PATH
    -v, --verbose           Enable debug output
    -h, --help              Show this help

EXAMPLES:
    $0 https://coder.example.com
    $0 --insecure https://coder.internal.com
    $0 --dir ~/bin --auto-path https://coder.example.com

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -s|--skip-verify)
            SKIP_VERIFY=1
            shift
            ;;
        -k|--insecure)
            INSECURE=1
            shift
            ;;
        -p|--auto-path)
            AUTO_PATH=1
            shift
            ;;
        -v|--verbose)
            DEBUG=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
        *)
            CODER_URL="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$CODER_URL" ]; then
    print_error "No Coder URL provided"
    echo "Usage: $0 [OPTIONS] <coder-url>"
    exit 1
fi

CODER_URL=${CODER_URL%/}

if [[ ! $CODER_URL =~ ^https?:// ]]; then
    print_error "Invalid URL. Must start with http:// or https://"
    exit 1
fi

print_info "Coder CLI Installer v${VERSION}"
print_info "Coder URL: $CODER_URL"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        CODER_ARCH="amd64"
        ;;
    arm64|aarch64)
        CODER_ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

print_debug "Architecture: $ARCH -> $CODER_ARCH"

# Verify macOS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [ "$OS" != "darwin" ]; then
    print_error "This script is for macOS only. Detected: $OS"
    exit 1
fi

# Construct download URL
DOWNLOAD_URL="${CODER_URL}/bin/coder-darwin-${CODER_ARCH}"
print_info "Download URL: $DOWNLOAD_URL"

# Create temp directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT
print_debug "Temp directory: $TMP_DIR"

# Download binary
print_info "Downloading Coder CLI..."

if command -v curl &> /dev/null; then
    CURL_OPTS="-fSL"
    [ "$INSECURE" = "1" ] && CURL_OPTS="$CURL_OPTS -k"
    [ "$DEBUG" = "1" ] && CURL_OPTS="$CURL_OPTS -v"
    
    if [ "$DEBUG" = "1" ]; then
        HTTP_CODE=$(curl $CURL_OPTS -w "%{http_code}" -o "$TMP_DIR/coder" "$DOWNLOAD_URL" 2>&1 | tee "$TMP_DIR/curl.log" | tail -1 || echo "000")
    else
        HTTP_CODE=$(curl $CURL_OPTS -w "%{http_code}" -o "$TMP_DIR/coder" "$DOWNLOAD_URL" 2>/dev/null | tail -1 || echo "000")
    fi
    
    if [ "$HTTP_CODE" != "200" ]; then
        print_error "Download failed (HTTP $HTTP_CODE)"
        [ "$DEBUG" = "1" ] && [ -f "$TMP_DIR/curl.log" ] && cat "$TMP_DIR/curl.log"
        print_error "Verify:"
        print_error "  1. URL is correct: $CODER_URL"
        print_error "  2. Server is accessible"
        print_error "  3. /bin endpoint is enabled"
        exit 1
    fi
elif command -v wget &> /dev/null; then
    WGET_OPTS="-q"
    [ "$INSECURE" = "1" ] && WGET_OPTS="$WGET_OPTS --no-check-certificate"
    [ "$DEBUG" = "1" ] && WGET_OPTS="-v"
    
    if ! wget $WGET_OPTS -O "$TMP_DIR/coder" "$DOWNLOAD_URL" 2>&1 | tee "$TMP_DIR/wget.log"; then
        print_error "Download failed"
        [ "$DEBUG" = "1" ] && [ -f "$TMP_DIR/wget.log" ] && cat "$TMP_DIR/wget.log"
        exit 1
    fi
else
    print_error "Neither curl nor wget found"
    print_error "Install with: brew install curl"
    exit 1
fi

# Verify download
if [ ! -s "$TMP_DIR/coder" ]; then
    print_error "Downloaded file is empty"
    exit 1
fi

FILE_SIZE=$(stat -f%z "$TMP_DIR/coder" 2>/dev/null || echo "0")
print_debug "File size: $FILE_SIZE bytes"

if [ "$FILE_SIZE" -lt 1000000 ]; then
    print_warning "File size < 1MB, may not be valid"
fi

# Verify it's a Mach-O binary
if ! file "$TMP_DIR/coder" | grep -q "Mach-O"; then
    print_error "Not a valid macOS executable"
    print_debug "File type: $(file $TMP_DIR/coder)"
    
    if file "$TMP_DIR/coder" | grep -q "HTML"; then
        print_error "Received HTML instead of binary"
        [ "$DEBUG" = "1" ] && head -c 500 "$TMP_DIR/coder"
    fi
    exit 1
fi

print_info "Download successful"

# Make executable
chmod +x "$TMP_DIR/coder"

# Verify binary works
if [ "$SKIP_VERIFY" = "0" ]; then
    print_info "Verifying binary..."
    if "$TMP_DIR/coder" version &> /dev/null; then
        BINARY_VERSION=$("$TMP_DIR/coder" version 2>/dev/null | head -1 || echo "unknown")
        print_info "Binary version: $BINARY_VERSION"
    else
        print_warning "Verification failed, continuing anyway"
    fi
fi

# Determine install directory
if [ -n "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR"
elif [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
elif [ -w "$HOME/.local/bin" ]; then
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
fi

print_info "Installing to: $INSTALL_DIR"

# Backup existing
if [ -f "$INSTALL_DIR/coder" ]; then
    BACKUP="$INSTALL_DIR/coder.backup.$(date +%Y%m%d_%H%M%S)"
    print_warning "Backing up existing: $BACKUP"
    if [ -w "$INSTALL_DIR" ]; then
        mv "$INSTALL_DIR/coder" "$BACKUP"
    else
        sudo mv "$INSTALL_DIR/coder" "$BACKUP"
    fi
fi

# Install
if [ -w "$INSTALL_DIR" ]; then
    mv "$TMP_DIR/coder" "$INSTALL_DIR/coder"
else
    print_info "Installing with sudo..."
    sudo mv "$TMP_DIR/coder" "$INSTALL_DIR/coder"
fi

print_info "Installation successful!"

# Check PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    # Detect shell config
    if [ -n "$ZSH_VERSION" ] && [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_RC="$HOME/.bash_profile"
    elif [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.profile"
    fi
    
    if [ "$AUTO_PATH" = "1" ]; then
        echo "" >> "$SHELL_RC"
        echo "# Added by Coder CLI installer $(date +%Y-%m-%d)" >> "$SHELL_RC"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$SHELL_RC"
        print_info "Added to PATH in $SHELL_RC"
        print_info "Run: source $SHELL_RC"
    else
        echo ""
        print_warning "$INSTALL_DIR not in PATH"
        echo "Add it with:"
        echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> $SHELL_RC"
        echo "  source $SHELL_RC"
        echo ""
    fi
fi

# Final verification
INSTALLED_VERSION=$("$INSTALL_DIR/coder" version 2>/dev/null | head -1 || echo "unknown")
print_info "Installed version: $INSTALLED_VERSION"

# Success message
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_info "Installation complete! 🎉"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. coder login $CODER_URL"
echo "  2. coder create my-workspace"
echo "  3. coder ssh my-workspace"
echo ""
