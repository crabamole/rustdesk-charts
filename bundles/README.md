# RustDesk Installer Bundle

Pre-packaged RustDesk installers for corporate deployment.

## Contents

| File | Platform | Use Case |
|------|----------|----------|
| `rustdesk-*-x86_64.msi` | Windows | Full install (GPO/Intune, service, admin) |
| `rustdesk-*-x86_64.exe` | Windows | Client-only (portable, no admin) |
| `rustdesk-*-aarch64.dmg` | macOS | Full install or client-only |
| `rustdesk-*-x86_64.deb` | Linux | Full install (service, admin) |
| `rustdesk-*-x86_64.AppImage` | Linux | Client-only (portable, no admin) |

## Extract installers

```bash
docker create --name rustdesk-bundle ghcr.io/rophy/rustdesk/bundle:1.4.9
docker cp rustdesk-bundle:/bundles/installers ./installers
docker rm rustdesk-bundle
```

## Full install (with pre-seeded config)

Create `RustDesk2.toml` with your server settings:

```toml
[options]
custom-rendezvous-server = 'rustdesk.example.com'
api-server = 'https://rustdesk.example.com'
key = '<your-public-key>'
allow-websocket = 'Y'
disable-udp = 'Y'
direct-server = 'Y'
enable-udp-punch = 'N'
enable-lan-discovery = 'N'
allow-insecure-tls-fallback = 'Y'
```

### Windows

```powershell
# Pre-stage config
mkdir "$env:APPDATA\RustDesk\config" -Force
Copy-Item RustDesk2.toml "$env:APPDATA\RustDesk\config\RustDesk2.toml"

# Silent install
msiexec /i rustdesk-1.4.9-x86_64.msi /qn
```

### macOS

```bash
# Pre-stage config
mkdir -p ~/Library/Preferences/com.carriez.RustDesk
cp RustDesk2.toml ~/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml

# Install
hdiutil attach rustdesk-1.4.9-aarch64.dmg -nobrowse -quiet
sudo cp -R /Volumes/rustdesk-*/RustDesk.app /Applications/
hdiutil detach /Volumes/rustdesk-* -quiet

# User must click "Install" in the RustDesk UI to set up the service
open /Applications/RustDesk.app
```

### Linux

```bash
# Pre-stage config (both root and display user)
sudo mkdir -p /root/.config/rustdesk
sudo cp RustDesk2.toml /root/.config/rustdesk/RustDesk2.toml

# Also pre-stage for display user (e.g. lightdm)
DISPLAY_USER_HOME=$(eval echo ~$(ps -eo user,args | grep 'rustdesk --server' | grep -v grep | awk '{print $1}'))
# If fresh install, use lightdm as default:
sudo mkdir -p /var/lib/lightdm/.config/rustdesk
sudo cp RustDesk2.toml /var/lib/lightdm/.config/rustdesk/RustDesk2.toml

# Install
sudo dpkg -i rustdesk-1.4.9-x86_64.deb
```

## Client-only (outgoing connections only, no admin)

Create `custom.txt`:

```
conn-type = outgoing
disable-installation = Y
disable-tcp-listen = Y
```

### Windows

Place `custom.txt` in the same directory as the `.exe`, then run:

```powershell
.\rustdesk-1.4.9-x86_64.exe
```

### macOS

```bash
hdiutil attach rustdesk-1.4.9-aarch64.dmg -nobrowse -quiet
cp -R /Volumes/rustdesk-*/RustDesk.app ~/Desktop/RustDesk.app
hdiutil detach /Volumes/rustdesk-* -quiet

# Inject custom.txt
cp custom.txt ~/Desktop/RustDesk.app/Contents/Resources/custom.txt

open ~/Desktop/RustDesk.app
```

### Linux

Place `custom.txt` in the same directory as the AppImage:

```bash
chmod +x rustdesk-1.4.9-x86_64.AppImage
./rustdesk-1.4.9-x86_64.AppImage
```
