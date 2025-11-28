#!/bin/bash
# Superhuman Linux AppImage Build Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/superhuman-appimage-build-$$"
ELECTRON_VERSION="38.7.1"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
APPIMAGE_TOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

# First run the main build
log_info "=== Building Superhuman Linux AppImage ==="

# Check if base build exists
if [ ! -f "${OUTPUT_DIR}/superhuman-linux-x64.tar.gz" ]; then
    log_info "Running base build first..."
    "${SCRIPT_DIR}/build.sh"
fi

mkdir -p "$BUILD_DIR"

# Extract base build
log_info "Extracting base build..."
tar -xzf "${OUTPUT_DIR}/superhuman-linux-x64.tar.gz" -C "$BUILD_DIR"

# Create AppDir structure
log_info "Creating AppDir structure..."
APPDIR="${BUILD_DIR}/Superhuman.AppDir"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/lib"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Move app files
mv "${BUILD_DIR}/superhuman-linux/"* "${APPDIR}/usr/lib/"

# Create wrapper script
cat > "${APPDIR}/usr/bin/superhuman" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
APPDIR="$(dirname "$SCRIPT_DIR")"
export LD_LIBRARY_PATH="${APPDIR}/lib:${LD_LIBRARY_PATH}"
exec "${APPDIR}/lib/superhuman" --no-sandbox "$@"
EOF
chmod +x "${APPDIR}/usr/bin/superhuman"

# Create desktop file
cat > "${APPDIR}/superhuman.desktop" << 'EOF'
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

cp "${APPDIR}/superhuman.desktop" "${APPDIR}/usr/share/applications/"

# Extract icon from Windows exe or use placeholder
log_info "Extracting icon..."
if command -v wrestool >/dev/null 2>&1 && command -v icotool >/dev/null 2>&1; then
    # Try to extract icon from Windows exe
    if [ -f "${SCRIPT_DIR}/Superhuman.exe" ]; then
        wrestool -x -t 14 "${SCRIPT_DIR}/Superhuman.exe" -o "${BUILD_DIR}/icon.ico" 2>/dev/null || true
        if [ -f "${BUILD_DIR}/icon.ico" ]; then
            icotool -x "${BUILD_DIR}/icon.ico" -o "${BUILD_DIR}/" 2>/dev/null || true
            # Find largest PNG
            ICON_FILE=$(ls -S "${BUILD_DIR}/"*_*x*.png 2>/dev/null | head -1)
            if [ -n "$ICON_FILE" ]; then
                cp "$ICON_FILE" "${APPDIR}/superhuman.png"
                cp "$ICON_FILE" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/superhuman.png"
            fi
        fi
    fi
fi

# Create placeholder icon if not extracted
if [ ! -f "${APPDIR}/superhuman.png" ]; then
    log_warn "Could not extract icon, using placeholder"
    # Create a simple SVG placeholder
    cat > "${APPDIR}/superhuman.svg" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" fill="#5046e5"/>
  <text x="128" y="150" font-size="120" text-anchor="middle" fill="white" font-family="Arial">S</text>
</svg>
EOF
    # Convert to PNG if possible
    if command -v convert >/dev/null 2>&1; then
        convert "${APPDIR}/superhuman.svg" "${APPDIR}/superhuman.png"
        cp "${APPDIR}/superhuman.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/"
    fi
fi

# Create AppRun
cat > "${APPDIR}/AppRun" << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/lib/superhuman" --no-sandbox "$@"
EOF
chmod +x "${APPDIR}/AppRun"

# Download appimagetool
log_info "Downloading appimagetool..."
wget -q --show-progress "$APPIMAGE_TOOL_URL" -O "${BUILD_DIR}/appimagetool"
chmod +x "${BUILD_DIR}/appimagetool"

# Build AppImage
log_info "Building AppImage..."
cd "$BUILD_DIR"

# Set ARCH for appimagetool
export ARCH=x86_64

"${BUILD_DIR}/appimagetool" --no-appstream "${APPDIR}" "${OUTPUT_DIR}/Superhuman-x86_64.AppImage" 2>&1 || {
    # Try with --appimage-extract-and-run if FUSE is not available
    log_warn "Trying with --appimage-extract-and-run..."
    "${BUILD_DIR}/appimagetool" --appimage-extract-and-run --no-appstream "${APPDIR}" "${OUTPUT_DIR}/Superhuman-x86_64.AppImage"
}

chmod +x "${OUTPUT_DIR}/Superhuman-x86_64.AppImage"

log_info "=== AppImage build complete! ==="
log_info "Output: ${OUTPUT_DIR}/Superhuman-x86_64.AppImage"
log_info ""
log_info "To run:"
log_info "  chmod +x Superhuman-x86_64.AppImage"
log_info "  ./Superhuman-x86_64.AppImage"
