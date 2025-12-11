#!/bin/bash
# Superhuman Linux Build Script
# Repackages the Windows Electron app for Linux
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/superhuman-linux-build-$$"
ELECTRON_VERSION="38.7.1"
OUTPUT_DIR="${SCRIPT_DIR}/dist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

check_dependencies() {
    log_info "Checking dependencies..."
    local missing=()

    command -v 7z >/dev/null 2>&1 || missing+=("p7zip")
    command -v node >/dev/null 2>&1 || missing+=("nodejs")
    command -v npm >/dev/null 2>&1 || missing+=("npm")
    command -v wget >/dev/null 2>&1 || missing+=("wget")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Please install them and run again."
        exit 1
    fi

    log_info "All dependencies found."
}

extract_windows_installer() {
    log_info "Extracting Windows installer..."

    local exe_path="${SCRIPT_DIR}/Superhuman.exe"
    if [ ! -f "$exe_path" ]; then
        log_error "Superhuman.exe not found in ${SCRIPT_DIR}"
        log_error "Please download it from https://superhuman.com and place it here."
        exit 1
    fi

    mkdir -p "${BUILD_DIR}/extract"
    7z x -y "$exe_path" -o"${BUILD_DIR}/extract" > /dev/null

    # Extract the app from app-64.7z
    mkdir -p "${BUILD_DIR}/app-win"
    7z x -y "${BUILD_DIR}/extract/\$PLUGINSDIR/app-64.7z" -o"${BUILD_DIR}/app-win" > /dev/null

    # Get version from the extracted app
    SUPERHUMAN_VERSION=$(strings "${BUILD_DIR}/app-win/Superhuman.exe" 2>/dev/null | grep -oP 'Electron/\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "38.7.1")
    log_info "Detected Electron version: ${SUPERHUMAN_VERSION}"
}

download_electron() {
    log_info "Downloading Electron ${ELECTRON_VERSION} for Linux x64..."

    mkdir -p "${BUILD_DIR}/electron"
    wget -q --show-progress \
        "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip" \
        -O "${BUILD_DIR}/electron/electron.zip"

    cd "${BUILD_DIR}/electron"
    unzip -q electron.zip
    rm electron.zip
}

install_asar_tool() {
    log_info "Installing asar tool..."
    cd "${BUILD_DIR}"
    npm install @electron/asar || { log_error "Failed to install asar tool"; exit 1; }
}

extract_and_patch_asar() {
    log_info "Extracting and patching app.asar..."

    mkdir -p "${BUILD_DIR}/asar-contents"
    cd "${BUILD_DIR}"
    npx @electron/asar extract \
        "${BUILD_DIR}/app-win/resources/app.asar" \
        "${BUILD_DIR}/asar-contents"

    # Apply Linux patches
    apply_patches

    # Repack
    log_info "Repacking app.asar..."
    npx @electron/asar pack \
        "${BUILD_DIR}/asar-contents" \
        "${BUILD_DIR}/app.asar"
}

apply_patches() {
    log_info "Applying Linux compatibility patches..."

    local src_dir="${BUILD_DIR}/asar-contents/src"
    local main_entry="${BUILD_DIR}/asar-contents/main.js"

    # Patch 1: native_memory_poller.js - Add Linux support
    sed -i "s/if (process.platform === 'darwin') {/if (process.platform === 'darwin' || process.platform === 'linux') {/g" \
        "${src_dir}/native_memory_poller.js"

    # Patch 2: updater.js - Skip updates on Linux
    sed -i "/if (appConfig.isDev) {/a\\
\\    // Linux auto-updates not supported - skip gracefully\\
\\    if (process.platform === 'linux') {\\
\\      return\\
\\    }" "${src_dir}/updater.js"

    # Patch 3: window.js - Use Windows shortcuts for Linux
    sed -i "s/} else if (process.platform === 'win32') {$/} else if (process.platform === 'win32' || process.platform === 'linux') {/g" \
        "${src_dir}/window.js"

    # Patch 4: window.js - Zoom control key for Linux
    sed -i "s/(process.platform === 'win32' && input.control)/((process.platform === 'win32' || process.platform === 'linux') \&\& input.control)/g" \
        "${src_dir}/window.js"

    # Patch 5: main.js (entry point) - Add Linux argv URL check like Windows
    sed -i "s/} else if (process.platform === 'win32') {/} else if (process.platform === 'win32' || process.platform === 'linux') {/g" \
        "${src_dir}/main.js"

    # Patch 6: main.js - Fix async download handler by making mkdir synchronous
    # Electron's will-download event doesn't properly await async handlers,
    # so we need to ensure setSavePath is called synchronously
    sed -i 's/await fs\.promises\.mkdir(downloadsLocation, { recursive: true })/fs.mkdirSync(downloadsLocation, { recursive: true })/g' \
        "${src_dir}/main.js"

    log_info "Patches applied successfully."
}

assemble_app() {
    log_info "Assembling Linux application..."

    mkdir -p "${BUILD_DIR}/superhuman-linux/resources"

    # Copy Electron files
    cp -r "${BUILD_DIR}/electron/"* "${BUILD_DIR}/superhuman-linux/"

    # Remove default app
    rm -f "${BUILD_DIR}/superhuman-linux/resources/default_app.asar"

    # Copy patched app.asar
    cp "${BUILD_DIR}/app.asar" "${BUILD_DIR}/superhuman-linux/resources/"

    # Rename electron binary to superhuman-bin
    mv "${BUILD_DIR}/superhuman-linux/electron" "${BUILD_DIR}/superhuman-linux/superhuman-bin"

    # Create wrapper script that handles OAuth URL conversion
    cat > "${BUILD_DIR}/superhuman-linux/superhuman" << 'WRAPPER'
#!/bin/bash
# Superhuman Linux wrapper script
# Handles OAuth callback URL conversion

# Resolve symlinks to find actual script location
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
URL=""

# Process arguments to find and convert URLs
ARGS=()
for arg in "$@"; do
    if [[ "$arg" == superhuman://login* ]]; then
        # Convert superhuman://login to superhuman://~login (app expects tilde prefix)
        URL="${arg/superhuman:\/\/login/superhuman://~login}"
        ARGS+=("$URL")
    else
        ARGS+=("$arg")
    fi
done

# Launch the actual binary with --no-sandbox (required on most Linux systems)
exec "${SCRIPT_DIR}/superhuman-bin" --no-sandbox "${ARGS[@]}"
WRAPPER
    chmod +x "${BUILD_DIR}/superhuman-linux/superhuman"

    # Create desktop file
    cat > "${BUILD_DIR}/superhuman-linux/superhuman.desktop" << 'EOF'
[Desktop Entry]
Name=Superhuman
Comment=The fastest email experience ever made
Exec=superhuman %U
Icon=superhuman
Type=Application
Categories=Network;Email;
MimeType=x-scheme-handler/mailto;x-scheme-handler/superhuman;
StartupWMClass=Superhuman
Terminal=false
EOF

    # Copy icon if available
    if [ -f "${SCRIPT_DIR}/assets/superhuman.png" ]; then
        cp "${SCRIPT_DIR}/assets/superhuman.png" "${BUILD_DIR}/superhuman-linux/"
    fi

    # Create login helper script for OAuth callback
    cat > "${BUILD_DIR}/superhuman-linux/superhuman-login" << 'LOGINHELPER'
#!/bin/bash
# Superhuman Linux Login Helper
# Converts the OAuth callback URL and passes it to the app

# Resolve symlinks to find actual script location
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
URL="$1"

if [ -z "$URL" ]; then
    echo "Superhuman Linux Login Helper"
    echo ""
    echo "Usage: superhuman-login 'OAUTH_URL'"
    echo ""
    echo "After Google sign-in, copy the full URL from your browser"
    echo "(starts with https://mail.superhuman.com/~login#...)"
    echo "and pass it to this script."
    exit 1
fi

# Convert HTTPS URL to superhuman:// protocol
if [[ "$URL" == https://mail.superhuman.com/* ]]; then
    CONVERTED=$(echo "$URL" | sed 's|https://mail.superhuman.com/|superhuman://|')
elif [[ "$URL" == superhuman://* ]]; then
    CONVERTED="$URL"
    if [[ "$CONVERTED" == superhuman://login* ]]; then
        CONVERTED="${CONVERTED/superhuman:\/\/login/superhuman://~login}"
    fi
else
    echo "Error: URL must start with https://mail.superhuman.com/ or superhuman://"
    exit 1
fi

echo "Logging in..."
"${SCRIPT_DIR}/superhuman" "$CONVERTED"
LOGINHELPER
    chmod +x "${BUILD_DIR}/superhuman-linux/superhuman-login"
}

create_output() {
    log_info "Creating output..."

    mkdir -p "$OUTPUT_DIR"

    # Create install script
    cat > "${BUILD_DIR}/superhuman-linux/install.sh" << 'INSTALL'
#!/bin/bash
# Superhuman Linux Installer
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${HOME}/.local/share/superhuman"
BIN_DIR="${HOME}/.local/bin"
APPS_DIR="${HOME}/.local/share/applications"
ICONS_DIR="${HOME}/.local/share/icons/hicolor/256x256/apps"

echo "Installing Superhuman..."

# Create directories
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APPS_DIR" "$ICONS_DIR"

# Copy files
cp -r "${SCRIPT_DIR}"/* "$INSTALL_DIR/"
chmod +x "${INSTALL_DIR}/superhuman"
chmod +x "${INSTALL_DIR}/superhuman-bin"
chmod +x "${INSTALL_DIR}/superhuman-login"
chmod +x "${INSTALL_DIR}/chrome_crashpad_handler"
chmod +x "${INSTALL_DIR}/chrome-sandbox" 2>/dev/null || true

# Create symlinks in bin
ln -sf "${INSTALL_DIR}/superhuman" "${BIN_DIR}/superhuman"
ln -sf "${INSTALL_DIR}/superhuman-login" "${BIN_DIR}/superhuman-login"

# Install icon
if [ -f "${INSTALL_DIR}/superhuman.png" ]; then
    cp "${INSTALL_DIR}/superhuman.png" "$ICONS_DIR/"
fi

# Install and update desktop file
sed "s|Exec=superhuman|Exec=${INSTALL_DIR}/superhuman|g" \
    "${INSTALL_DIR}/superhuman.desktop" > "${APPS_DIR}/superhuman.desktop"
sed -i "s|Icon=superhuman|Icon=${ICONS_DIR}/superhuman.png|g" \
    "${APPS_DIR}/superhuman.desktop"

# Register protocol handlers
xdg-mime default superhuman.desktop x-scheme-handler/superhuman
xdg-mime default superhuman.desktop x-scheme-handler/mailto

# Update desktop database
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
fi

echo ""
echo "Installation complete!"
echo ""
echo "You can now:"
echo "  - Run 'superhuman' from terminal (add ~/.local/bin to PATH if needed)"
echo "  - Find Superhuman in your application launcher"
echo "  - Sign in with Google (OAuth callbacks will work automatically)"
INSTALL
    chmod +x "${BUILD_DIR}/superhuman-linux/install.sh"

    # Create tarball
    cd "${BUILD_DIR}"
    tar -czvf "${OUTPUT_DIR}/superhuman-linux-x64.tar.gz" -C "${BUILD_DIR}" superhuman-linux

    log_info "Build complete!"
    log_info "Output: ${OUTPUT_DIR}/superhuman-linux-x64.tar.gz"
    log_info ""
    log_info "To install:"
    log_info "  tar -xzf superhuman-linux-x64.tar.gz"
    log_info "  cd superhuman-linux"
    log_info "  ./install.sh"
    log_info ""
    log_info "Or to run directly:"
    log_info "  ./superhuman"
}

main() {
    log_info "=== Superhuman Linux Build Script ==="
    log_info "Build directory: ${BUILD_DIR}"

    mkdir -p "$BUILD_DIR"

    check_dependencies
    extract_windows_installer
    download_electron
    install_asar_tool
    extract_and_patch_asar
    assemble_app
    create_output

    log_info "=== Build completed successfully! ==="
}

main "$@"
