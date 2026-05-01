# TinkerPro Employee — Build Guide

Lightweight desktop chat client for store employees. Identifies them by **store name** (one-time setup, persisted across reinstalls) and connects them to admin support via the same backend the staff/customer apps use. Ships text chat, voice/video calls, and same-store LAN "Add a colleague" discovery.

This guide covers building and running it on:

- [Linux desktop](#linux-desktop) (Fedora / Ubuntu / Debian)
- [Windows](#windows) (`.exe`)
- [Android](#android) (`.apk` / `.aab`)
- [macOS](#macos) (when relevant)

---

## What you configure at build time

Five `--dart-define` flags. They're baked into the binary at compile time — to change them, rebuild:

| Flag | When you need it | Default |
|---|---|---|
| `TPS_BASE_URL` | **Always.** REST base URL for `api.php`. | `http://10.0.2.2/tinkerpro_support` (Android emulator host loopback) |
| `CHAT_SOKETI_HOST` | When the Soketi WebSocket is on a different host than the API (e.g. ngrok-only forwarding the API). | Same host as the API URL |
| `CHAT_SOKETI_PORT` | When Soketi is fronted by Apache/nginx on `:443` (production) instead of direct on `:6001`. | `6001` |
| `CHAT_SOKETI_TLS` | When connecting via `wss://` (anything HTTPS). | Matches API URL scheme |
| `CHAT_SOKETI_KEY` | If you rotated the public Soketi key off the dev default. | `tinkerpro-chat-key` |

**Three URL recipes covering every realistic deployment:**

```bash
# 1. Local XAMPP, same machine — Linux desktop dev
--dart-define=TPS_BASE_URL=http://localhost/tinkerpro_support

# 2. Phone/Windows on the same Wi-Fi as your dev box
--dart-define=TPS_BASE_URL=http://192.168.1.42/tinkerpro_support

# 3. ngrok tunnel (or production HTTPS host)
--dart-define=TPS_BASE_URL=https://your-tunnel.ngrok-free.dev/tinkerpro_support \
--dart-define=CHAT_SOKETI_HOST=your-tunnel.ngrok-free.dev \
--dart-define=CHAT_SOKETI_PORT=443 \
--dart-define=CHAT_SOKETI_TLS=true
```

For recipe 3 to work end-to-end, your Apache vhost behind ngrok must reverse-proxy `/ws/` to local Soketi `:6001`. Without that, chat HTTP works but realtime and call signaling won't reach Soketi. See `docs/chat-vps-setup.md §6` on the server repo.

---

## Linux desktop

### Prereqs (one-time)

Fedora:

```bash
sudo dnf install -y \
    gstreamer1-devel gstreamer1-plugins-base-devel \
    clang cmake ninja-build pkgconf-pkg-config \
    gtk3-devel libsecret-devel
```

Ubuntu / Debian:

```bash
sudo apt install -y \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev libsecret-1-dev
```

Flutter itself: install per the [official docs](https://docs.flutter.dev/get-started/install/linux/desktop) and confirm `flutter doctor` shows no red dots for Linux.

### Build

```bash
cd ~/Documents/tinkerpro_supports/employee_app
flutter pub get
flutter build linux \
    --dart-define=TPS_BASE_URL=http://localhost/tinkerpro_support
```

Output: `build/linux/x64/release/bundle/`. The whole folder ships together; the `employee_app` ELF binary on its own won't run (it loads `data/flutter_assets/` for the icon + Flutter engine).

### Run / develop

```bash
# Hot-reload dev cycle
flutter run -d linux \
    --dart-define=TPS_BASE_URL=http://localhost/tinkerpro_support

# Run the release build directly
./build/linux/x64/release/bundle/employee_app
```

### Distribute

Tar the bundle:

```bash
cd build/linux/x64/release/bundle
tar -czf ~/employee_app-linux-x64.tar.gz .
```

Recipient extracts, runs `./employee_app`. No installer needed for in-house distribution.

---

## Windows

### Prereqs (one-time, on a Windows machine)

- Windows 10 or 11.
- **Visual Studio 2022** (Community is fine) with the **"Desktop development with C++"** workload — this is what provides the C++ toolchain Flutter needs. The free Build Tools alone is not enough; you need the full IDE for the SDK headers.
- Flutter SDK on the same channel/version you use elsewhere.
- Run `flutter doctor` — it must report **Windows** as ✓ green.

### Build

From PowerShell or Command Prompt in the project directory:

```powershell
flutter pub get
flutter build windows ^
    --dart-define=TPS_BASE_URL=https://your-tunnel.ngrok-free.dev/tinkerpro_support ^
    --dart-define=CHAT_SOKETI_HOST=your-tunnel.ngrok-free.dev ^
    --dart-define=CHAT_SOKETI_PORT=443 ^
    --dart-define=CHAT_SOKETI_TLS=true
```

Output: `build\windows\x64\runner\Release\`. Inside you'll find:

```
Release\
├── employee_app.exe
├── flutter_windows.dll
├── *.dll              ← plugin native libs
└── data\
    ├── icudtl.dat
    └── flutter_assets\
        └── assets\brand\tinkerpro-icon-512.png
```

**The whole `Release\` folder ships together.** Renaming or moving the .exe out of it will break the app at startup.

### Cross-compile from Linux

Not possible. Flutter Windows builds require a Windows host with the Visual Studio C++ toolchain. If you only have a Linux dev machine, options are:

- Build on a Windows VM (VirtualBox / VMware / Hyper-V).
- Build on a Windows VPS or cloud instance.
- GitHub Actions / Codemagic with a Windows runner — a workflow that runs `flutter build windows` and uploads the artifact.

### Distribute

Zip the entire `Release\` folder. For polished distribution, use **Inno Setup** or **MSIX** to produce a proper installer — but for in-house deployment, a zip + a shortcut is enough.

### Windows-specific TODO

The `.exe` icon shown in File Explorer is currently the Flutter blue default. The TinkerPro icon is bundled as a Flutter asset and used for the *window* icon at runtime, but the *executable* icon Windows shows in shortcuts and task switcher needs a separate `.ico` resource embedded into `Runner.rc`:

1. Convert the PNG to `.ico`:
   ```powershell
   # Requires ImageMagick
   magick assets\brand\tinkerpro-icon-512.png -define icon:auto-resize=64,48,32,16 windows\runner\resources\app_icon.ico
   ```
2. Edit `windows\runner\Runner.rc` and point `IDI_APP_ICON` at the new `.ico`.
3. Rebuild.

---

## Android

### Prereqs

- Android Studio with Android SDK + an emulator OR a physical device with USB debugging on.
- Confirm `flutter doctor` shows **Android toolchain** as ✓.

### Build

**Debug install on a connected device** (fastest dev cycle):

```bash
flutter run \
    --dart-define=TPS_BASE_URL=https://your-tunnel.ngrok-free.dev/tinkerpro_support
```

**Release APK** (sideloadable):

```bash
flutter build apk \
    --dart-define=TPS_BASE_URL=https://your-tunnel.ngrok-free.dev/tinkerpro_support \
    --dart-define=CHAT_SOKETI_HOST=your-tunnel.ngrok-free.dev \
    --dart-define=CHAT_SOKETI_PORT=443 \
    --dart-define=CHAT_SOKETI_TLS=true
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (~25–40 MB).

**Play Store bundle** (`.aab`):

```bash
flutter build appbundle --release \
    --dart-define=TPS_BASE_URL=https://your-prod-host/tinkerpro_support \
    --dart-define=CHAT_SOKETI_HOST=your-prod-host \
    --dart-define=CHAT_SOKETI_PORT=443 \
    --dart-define=CHAT_SOKETI_TLS=true
```

### Android-specific notes

- **First-run permissions:** the OS will prompt for microphone (always) and camera (if a video call is initiated). Decline → no calls; chat still works.
- **LAN "Add participant" picker** uses UDP broadcast on `:56789`. Some Wi-Fi routers / corporate firewalls block UDP broadcast; in that case the picker will show "no peers". The chat itself doesn't depend on it.
- **Emulator → host loopback:** the default `TPS_BASE_URL` is `http://10.0.2.2/tinkerpro_support`, which is the AOSP emulator's alias for the host machine. So if you `flutter run` on an emulator with no `--dart-define`, it'll try to reach your host's XAMPP. Real devices need a real LAN/WAN URL.

---

## macOS

Same shape as Linux + Windows — Flutter supports it but you need a Mac to build.

```bash
flutter build macos \
    --dart-define=TPS_BASE_URL=https://your-host/tinkerpro_support \
    --dart-define=CHAT_SOKETI_HOST=your-host \
    --dart-define=CHAT_SOKETI_PORT=443 \
    --dart-define=CHAT_SOKETI_TLS=true
```

Output: `build/macos/Build/Products/Release/employee_app.app` — a `.app` bundle. Distributable via DMG or notarized for the App Store. macOS isn't in the current `flutter create --platforms` config; if you need it, run:

```bash
flutter create --platforms=macos .
```

…to scaffold the `macos/` directory, then build.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `CMake Error: gstreamer-1.0 not found` (Linux) | Missing GStreamer dev libs | Install per the prereqs section |
| `cmake_install.cmake: file INSTALL cannot copy file ... Permission denied` (Linux) | Stale CMake cache or `CMAKE_INSTALL_PREFIX=/usr/local` in env | `flutter clean`, `unset CMAKE_INSTALL_PREFIX`, retry |
| `MissingPluginException` after adding a plugin | Hot-reloaded but didn't recompile native | Stop the app fully, `flutter clean`, `flutter pub get`, `flutter run` |
| Chat works but messages don't appear in real time | Soketi unreachable from the device | Confirm `--dart-define` Soketi flags match your tunnel/server. `tail /var/log/soketi.log` on the server side. |
| Calls connect but no audio | Mic permission denied OR no input device | Check OS settings for the app's mic permission. On Linux: `pavucontrol` to verify input source is set. |
| "No colleagues detected on this network" in the Add picker | UDP broadcast blocked (corporate Wi-Fi, VLAN, or two devices not on the same subnet) | Test by running two instances of the app on the same Wi-Fi LAN. |
| Re-install lost the chat history | `shared_preferences` data dir was wiped | User just re-enters the **same store name** on first launch. The server matches by name (`chat.employeeStart` → `findOrCreateEmployeeConversation`) and resumes the same thread. |

---

## Quick reference — what file does what

```
employee_app/
├── lib/
│   ├── main.dart                    ← entry point, decides setup vs chat at launch
│   ├── api_client.dart              ← cookie-aware Dio HTTP, persistent session
│   ├── theme.dart                   ← Brand colors
│   ├── models/chat_models.dart      ← Message, Participant, etc.
│   ├── services/
│   │   ├── chat_service.dart        ← REST: history, send, employeeStart, addToConversation
│   │   ├── chat_realtime.dart       ← Soketi WebSocket (Pusher protocol)
│   │   ├── call_service.dart        ← WebRTC + chat.signal flow
│   │   ├── ringtone_service.dart    ← In-app audio cues
│   │   ├── lan_presence.dart        ← UDP-broadcast same-store discovery
│   │   └── session_store.dart       ← SharedPreferences for store name + identity
│   └── screens/
│       ├── store_setup_screen.dart  ← First-launch: enter store name
│       ├── chat_screen.dart         ← Main chat surface + Add Participant picker
│       └── call_screen.dart         ← Voice/video call full-screen UI
├── assets/brand/tinkerpro-icon-512.png
├── linux/                           ← GTK runner (custom: window icon + title patch)
├── windows/                         ← Win32 runner (default scaffold)
├── android/                         ← Android Gradle build
└── pubspec.yaml                     ← Dependencies
```

If something breaks and you don't recognize a file path in the error message, that's where to look.
