# Downloads

Prebuilt installers for macOS, Windows, and Linux.

## Download

| Platform | Installer |
|----------|-----------|
| macOS (Apple Silicon) | [**Download .dmg**](https://github.com/mengo-consulting-group/public/releases/latest/download/c2-arm64.dmg) |
| Windows x64 | [**Download .exe**](https://github.com/mengo-consulting-group/public/releases/latest/download/c2-x64-setup.exe) |
| Linux x64 (AppImage) | [**Download .AppImage**](https://github.com/mengo-consulting-group/public/releases/latest/download/c2_x64.AppImage) |

[All releases →](https://github.com/mengo-consulting-group/public/releases)

## Installing

**macOS** — Open the `.dmg` and drag the app into `Applications`. Gatekeeper will say the app "is damaged and can't be opened" on first launch — open Terminal and run:

    xattr -dr com.apple.quarantine "/Applications/Open WebUI.app"

**Windows** — Run the `.exe` and follow the installer. SmartScreen will say "Windows protected your PC" — click **More info** → **Run anyway**.

**Linux** — Make the AppImage executable, then run it:

    chmod +x c2_x64.AppImage
    ./c2_x64.AppImage
