# Lessons Learned: Porting Electron Apps from Windows to Linux

This document captures lessons learned from porting Superhuman (Windows Electron app) to Linux. Use this as a guide for porting other Electron apps.

---

## 1. Initial Analysis

### Check if it's an Electron app
```bash
# Extract and look for Electron signatures
7z x AppName.exe -o/tmp/extract
find /tmp/extract -name "*.asar" -o -name "electron.exe"

# Check package.json in asar
npx @electron/asar extract app.asar /tmp/app-contents
cat /tmp/app-contents/package.json
```

### Identify Electron version
```bash
# From the extracted exe or from strings
strings AppName.exe | grep -oP 'Electron/\K[0-9]+\.[0-9]+\.[0-9]+'

# Or check package.json devDependencies
```

### Check for native modules (.node files)
```bash
find /tmp/app-contents -name "*.node"
```

**Important:** If native `.node` modules exist, you'll need to:
- Find Linux equivalents
- Rebuild them for Linux
- Or stub them out if non-essential

**Superhuman had NO native modules** - this made porting much easier.

---

## 2. Extraction Process

### Windows NSIS Installer
```bash
# Extract NSIS installer
7z x Installer.exe -o/tmp/extract

# Find the app archive (usually app-64.7z or similar)
7z x /tmp/extract/\$PLUGINSDIR/app-64.7z -o/tmp/app-win
```

### Extract app.asar
```bash
npm install @electron/asar
npx @electron/asar extract app.asar /tmp/asar-contents
```

---

## 3. Common Linux Patches Needed

### 3.1 Platform Checks
Search for platform-specific code:
```bash
grep -r "process.platform" /tmp/asar-contents/
grep -r "'darwin'" /tmp/asar-contents/
grep -r "'win32'" /tmp/asar-contents/
```

**Common pattern:** Add Linux alongside existing platforms:
```javascript
// Before
if (process.platform === 'darwin') { ... }
else if (process.platform === 'win32') { ... }

// After
if (process.platform === 'darwin' || process.platform === 'linux') { ... }
else if (process.platform === 'win32' || process.platform === 'linux') { ... }
```

### 3.2 Auto-Updater
Most Windows/Mac auto-updaters won't work on Linux. Disable gracefully:
```javascript
// Add at start of update function
if (process.platform === 'linux') {
  return  // Skip updates on Linux
}
```

### 3.3 System Commands
Apps using system commands need Linux equivalents:

| Function | macOS | Windows | Linux |
|----------|-------|---------|-------|
| Memory info | `ps -eo rss,comm` | WMIC | `ps -eo rss,comm` (same as macOS) |
| Open URL | `open` | `start` | `xdg-open` |
| File manager | `open -R` | `explorer /select` | `xdg-open` (directory only) |

### 3.4 Keyboard Shortcuts
Linux typically uses Ctrl (like Windows), not Cmd (macOS):
```javascript
// Ensure Linux uses Windows-style shortcuts
if (process.platform === 'win32' || process.platform === 'linux') {
  this._registerWindowsShortcuts(view)
}
```

### 3.5 URL Protocol Handling
On Windows/Linux, check `process.argv` for URLs on startup:
```javascript
// In main process startup
if (process.platform === 'win32' || process.platform === 'linux') {
  const url = process.argv.find(arg => arg.startsWith('myapp:'))
  if (url) {
    handleUrl(url)
  }
}
```

---

## 4. Electron Binary Replacement

### Download matching Electron version
```bash
ELECTRON_VERSION="38.7.1"  # Must match app's version!
wget "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip"
unzip electron-v${ELECTRON_VERSION}-linux-x64.zip -d electron/
```

### Assemble the app
```bash
mkdir -p app-linux/resources
cp -r electron/* app-linux/
rm app-linux/resources/default_app.asar
cp patched-app.asar app-linux/resources/app.asar
mv app-linux/electron app-linux/myapp
```

---

## 5. Wrapper Script (Important!)

Create a wrapper script to handle:
- `--no-sandbox` flag (required on most Linux systems)
- URL protocol conversion
- Environment variables

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Process URL arguments if needed
ARGS=()
for arg in "$@"; do
    # Add any URL transformations here
    ARGS+=("$arg")
done

exec "${SCRIPT_DIR}/myapp-bin" --no-sandbox "${ARGS[@]}"
```

---

## 6. Protocol Handler Registration

### Desktop file
```ini
[Desktop Entry]
Name=MyApp
Exec=/path/to/myapp %U
Icon=myapp
Type=Application
MimeType=x-scheme-handler/myapp;
Terminal=false
```

### Register handler
```bash
xdg-mime default myapp.desktop x-scheme-handler/myapp
update-desktop-database ~/.local/share/applications/
```

---

## 7. OAuth/Login Challenges

### Problem: Flatpak browsers can't trigger host protocol handlers

**Solution:** Create a login helper script:
```bash
#!/bin/bash
# Convert web URL to app protocol
URL="$1"
if [[ "$URL" == https://app.example.com/* ]]; then
    CONVERTED=$(echo "$URL" | sed 's|https://app.example.com/|myapp://|')
fi
/path/to/myapp "$CONVERTED"
```

### Problem: URL format mismatch
Some apps expect URLs in specific formats. Check:
- Does the app expect `myapp://path` or `myapp:path`?
- Are there path transformations needed (e.g., `login` → `~login`)?

**Debug with logging:**
```bash
echo "$(date): Received URL: $1" >> /tmp/myapp-handler.log
```

---

## 8. Flatpak Browser Considerations

Flatpak browsers (Firefox, Chrome) run sandboxed and may not:
- See host protocol handlers
- Be able to launch host applications

**Workarounds:**
1. Add Flatpak permissions:
```bash
flatpak override --user --filesystem=~/.local/share/applications:ro org.mozilla.firefox
```

2. Configure Firefox handlers:
```python
# Add to ~/.var/app/org.mozilla.firefox/.mozilla/firefox/PROFILE/handlers.json
{"schemes": {"myapp": {"action": 4}}}
```

3. Provide manual login helper (most reliable)

---

## 9. Build Script Template

```bash
#!/bin/bash
set -e

# Configuration
ELECTRON_VERSION="38.7.1"
APP_NAME="myapp"

# Extract Windows installer
7z x "${APP_NAME}.exe" -o"extract/"
7z x "extract/\$PLUGINSDIR/app-64.7z" -o"app-win/"

# Download Linux Electron
wget "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip"
unzip electron-*.zip -d electron/

# Extract and patch asar
npm install @electron/asar
npx @electron/asar extract app-win/resources/app.asar asar-contents/

# Apply patches here...
# sed -i 's/old/new/g' asar-contents/src/file.js

# Repack
npx @electron/asar pack asar-contents/ app.asar

# Assemble
mkdir -p "${APP_NAME}-linux/resources"
cp -r electron/* "${APP_NAME}-linux/"
cp app.asar "${APP_NAME}-linux/resources/"
mv "${APP_NAME}-linux/electron" "${APP_NAME}-linux/${APP_NAME}-bin"

# Create wrapper script
cat > "${APP_NAME}-linux/${APP_NAME}" << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/${APP_NAME}-bin" --no-sandbox "$@"
EOF
chmod +x "${APP_NAME}-linux/${APP_NAME}"

# Package
tar -czvf "${APP_NAME}-linux-x64.tar.gz" "${APP_NAME}-linux/"
```

---

## 10. Testing Checklist

- [ ] App launches without errors
- [ ] Basic functionality works
- [ ] Keyboard shortcuts work (Ctrl+C, Ctrl+V, etc.)
- [ ] Login/authentication works
- [ ] Protocol handler registered (`xdg-mime query default x-scheme-handler/myapp`)
- [ ] Protocol handler works (`xdg-open myapp://test`)
- [ ] App appears in application menu
- [ ] Icon displays correctly
- [ ] No sandbox errors (or handled with --no-sandbox)

---

## 11. Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "GPU process isn't usable" | GPU driver issues | Add `--disable-gpu` flag |
| Sandbox errors | Unprivileged user namespaces | Add `--no-sandbox` flag |
| Blank window | Wayland issues | Set `ELECTRON_OZONE_PLATFORM_HINT=auto` |
| Protocol handler not working | Browser sandboxing | Use manual login helper |
| App crashes on start | Wrong Electron version | Match exact version from Windows app |
| Native module errors | .node files are Windows binaries | Rebuild for Linux or stub out |
| File downloads show picker | Async `will-download` handler | Use sync `fs.mkdirSync()` before `setSavePath()` |
| Download progress stuck | Async handler race condition | Ensure `setSavePath()` called synchronously |

---

## 12. File Downloads & Async Event Handlers

### Problem: Electron's `will-download` event doesn't await async handlers

If your download handler is async and uses `await` before calling `setSavePath()`, Electron may start the download before the path is set, causing:
- File picker dialog to appear instead of direct save
- Progress bar stuck/not updating
- "Show in folder" button not working

**Bad pattern:**
```javascript
async _onFileWillDownload(event, item, webContents) {
  // DON'T DO THIS - await before setSavePath
  await fs.promises.mkdir(downloadsLocation, { recursive: true })
  item.setSavePath(temporarySavePath)  // Too late!
}
```

**Good pattern:**
```javascript
async _onFileWillDownload(event, item, webContents) {
  // Use sync version to ensure setSavePath is called immediately
  fs.mkdirSync(downloadsLocation, { recursive: true })
  item.setSavePath(temporarySavePath)  // Called synchronously!

  // Async operations are fine AFTER setSavePath
  item.on('done', async () => {
    await someAsyncCleanup()
  })
}
```

**Patch example:**
```bash
sed -i 's/await fs\.promises\.mkdir(downloadsLocation, { recursive: true })/fs.mkdirSync(downloadsLocation, { recursive: true })/g' \
    "${src_dir}/main.js"
```

---

## 14. Resources

- [Electron Documentation](https://www.electronjs.org/docs)
- [electron-builder](https://www.electron.build/) - For proper multi-platform builds
- [claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) - Reference project
- [AppImage documentation](https://docs.appimage.org/)
- [Flatpak documentation](https://docs.flatpak.org/)

---

## 13. Legal Considerations

- Don't distribute the original app code
- Require users to download the original installer themselves
- Clearly mark as "unofficial"
- Respect trademarks in naming

---

*Document created from Superhuman Linux porting project, November 2025*
