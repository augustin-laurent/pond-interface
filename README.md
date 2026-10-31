# Pond Interface

Desktop shell, lock screen, login screen and screenshot UI for Pond on Niri.
This fork includes English/French localization, bottom and sidebar layouts,
and per-workspace scrolling/floating modes.

## Build

Requirements: Qt 6.11+ (Core, Gui, Qml, Quick, DBus), KF6 NetworkManagerQt,
Wayland client development files, pkg-config, CMake, and a C++ compiler.
The runtime also needs Quickshell and Niri.

```sh
cmake -S . -B build
cmake --build build -j4
```

The native modules are `Pond.System` (network, sleep/lock and Caps Lock),
`Pond.Localization`, and `Pond.Screenshot.Native`. Install the matching modules
and QML files together; copying only the QML files is insufficient.

See [localization and installation](docs/localization.md) for translation
authoring and installation, and
[workspace modes](docs/workspace-modes.md) for layout and drag behavior.
