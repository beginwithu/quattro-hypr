# Quattro shell

The Quattro desktop runs inside one long-lived [Quickshell](https://quickshell.outfoxxed.me/) process (`quickshell -n -p "$QUATTRO_PATH/shell"`), launched with `QS_DISABLE_FILE_WATCHER=1` by [`bin/quattro-launch-shell`](../bin/quattro-launch-shell) and controlled over IPC via [`bin/quattro-shell`](../bin/quattro-shell).

## Layout

- `shell.qml` — main `ShellRoot` host. Owns shared service instances (`PluginRegistry`, `BarWidgetRegistry`, `AppLibrary`, `BrightnessKeys`, `BackgroundIntro`, `BackgroundSwitch`), loads `shell.json`, registers IPC handlers, and mounts enabled plugins.
- `screensaver.qml` & `share-picker.qml` — standalone Quickshell entry points for fullscreen screensaver and XDPH portal screen-share selection when invoked outside the main host.
- `Commons/` (`module qs.Commons`) — shared singletons and pure JS models (`AudioNodes`, `Border`, `Color`, `I18n`, `InputDevices`, `InputMethodState`, `IpcRegistry`, `ShellIpc`, `Style`, `Translations`, `UntypedInput`, `Util`).
- `Ui/` (`module qs.Ui`) — reusable themed QML controls (`BarWidget`, `BarIconButton`, `BarIndicator`, `BorderSurface`, `OverlayWindow`, `Panel`, `PanelController`, `PopupCard`, `FilterInput`, `Button`, `ToggleSwitch`, etc.).
- `services/` — host-level QML/JS services (`PluginRegistry.qml`, `BarWidgetRegistry.qml`, `AppLibrary.qml`, `AppSearch.js`, `hidden-entries.sh`, `BrightnessKeys.qml`, `BackgroundIntro.qml`, `BackgroundSwitch.qml`).
- `plugins/` — bundled first-party plugins (`bar`, `dock`, `menu`, `osd`, `notifications`, `lock`, `polkit`, `background`, `clipboard`, `emojis`, `image-picker`, `screensaver`, `share-picker`, `panels/*`, `services/*`). See [`plugins/README.md`](plugins/README.md) and [`plugins/bar/README.md`](plugins/bar/README.md).

## Configuration (`shell.json`)

Out of the box, the host reads [`config/quattro/shell.json`](../config/quattro/shell.json). Once `~/.config/quattro/shell.json` exists (created by bar drag gestures, `quattro bar ...`, `quattro dock ...`, `quattro plugin ...`, or manual edits), the user file becomes canonical without deep-merging.

## Reloading & IPC

```bash
quattro-shell shell ping
quattro-shell shell reloadConfig
quattro-shell shell rescanPlugins
quattro-restart-shell
```
