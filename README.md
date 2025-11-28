# Superhuman Linux

Unofficial Linux build of [Superhuman](https://superhuman.com) email client.

This project repackages the Windows Electron app to work on Linux, similar to [claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian).

## Quick Start

### Download Superhuman

First, download `Superhuman.exe` from [superhuman.com](https://superhuman.com) and place it in this directory.

### Build and Install

```bash
# Build the Linux version
./build.sh

# Extract and install
tar -xzf dist/superhuman-linux-x64.tar.gz
cd superhuman-linux
./install.sh
```

The installer will:
- Install to `~/.local/share/superhuman/`
- Create a symlink in `~/.local/bin/superhuman`
- Register the desktop file and icon
- Configure the `superhuman://` protocol handler for Google OAuth

### Run

After installation:
- Run `superhuman` from terminal (ensure `~/.local/bin` is in your PATH)
- Or find "Superhuman" in your application launcher

### Alternative: Run without installing

```bash
tar -xzf dist/superhuman-linux-x64.tar.gz
cd superhuman-linux
./superhuman
```

## Google Sign-In

### Option A: Automatic (if browser supports protocol handlers)

1. Click "Sign in with Google" in the app
2. Complete authentication in your browser
3. When prompted, allow opening the `superhuman://` link
4. The app will automatically receive the OAuth callback

### Option B: Manual (for Flatpak browsers or if automatic fails)

If your browser doesn't prompt to open Superhuman (common with Flatpak Firefox/Chrome):

1. Click "Sign in with Google" in the app
2. Complete authentication in your browser
3. After Google auth, you'll land on a page like `https://mail.superhuman.com/~login#...`
4. Copy the full URL from the browser address bar
5. Run the login helper:

```bash
superhuman-login 'https://mail.superhuman.com/~login#code=...'
```

The login helper converts the URL and passes it to the app.

## Build Options

### Option 1: Tarball (recommended)

```bash
./build.sh
```

### Option 2: AppImage

```bash
./build-appimage.sh
./dist/Superhuman-x86_64.AppImage
```

### Option 3: Flatpak

```bash
flatpak-builder --user --install --force-clean build-dir com.superhuman.Superhuman.yml
flatpak run com.superhuman.Superhuman
```

## Dependencies

### For build.sh
- `p7zip` - Extract Windows installer
- `nodejs` and `npm` - For asar tool
- `wget` - Download Electron

### For AppImage
- All of the above plus `appimagetool` (downloaded automatically)

### For Flatpak
- `flatpak-builder`
- Freedesktop SDK

### Optional (for icon extraction)
- `icoutils` - Extract icons from Windows exe

## How It Works

1. **Extract** the Windows NSIS installer using 7-Zip
2. **Extract** `app.asar` from the Electron app resources
3. **Patch** the JavaScript for Linux compatibility:
   - Memory poller: Use `ps` command (same as macOS)
   - Auto-updater: Disabled (no Linux update channel)
   - Keyboard shortcuts: Use Ctrl-based shortcuts like Windows
   - URL handling: Handle `superhuman://` protocol on Linux
4. **Repack** the modified `app.asar`
5. **Create wrapper script** that handles OAuth URL conversion
6. **Combine** with Linux Electron binary
7. **Package** with installer script

## File Structure

After building:
```
superhuman-linux/
├── superhuman          # Wrapper script (handles URLs, adds --no-sandbox)
├── superhuman-bin      # Actual Electron binary
├── superhuman.desktop  # Desktop file template
├── superhuman.png      # App icon
├── install.sh          # Installer script
├── resources/
│   └── app.asar        # Patched Superhuman app
└── ... (Electron files)
```

## Known Limitations

- **No auto-updates**: Updates must be done manually by rebuilding
- **Badge icon**: Desktop badge notifications may not work on all Linux desktops
- **Tray icon**: System tray support varies by desktop environment

## Troubleshooting

### "GPU process isn't usable"
Run with `--disable-gpu` or ensure you have proper GPU drivers installed.

### Sandbox errors
The wrapper script automatically adds `--no-sandbox`. If you run `superhuman-bin` directly, add this flag manually.

### Wayland issues
Set `ELECTRON_OZONE_PLATFORM_HINT=auto` for automatic X11/Wayland detection, or use `--ozone-platform=x11` to force X11.

### Google Sign-In not working
Make sure the protocol handler is registered:
```bash
xdg-mime query default x-scheme-handler/superhuman
```
Should return `superhuman.desktop`. If not, re-run the installer or manually register:
```bash
xdg-mime default superhuman.desktop x-scheme-handler/superhuman
```

### OAuth callback URL issues
Check `/tmp/superhuman-wrapper.log` for URL conversion debugging.

## Legal

This is an unofficial project. Superhuman is a trademark of Superhuman Labs, LLC.
This project does not distribute any Superhuman code - users must download Superhuman.exe themselves.

## Credits

Inspired by [claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian).
