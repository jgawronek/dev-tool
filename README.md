# DevUtils

DevUtils is a native macOS desktop app built with Flutter. It provides a local toolbox for common developer tasks such as JSON formatting, Base64 conversion, JWT debugging, URL parsing, hashing, text transforms, color conversion, MIME lookup, and offline LLM experiments.

The app is designed to be fast, offline-first, and easy to extend through the central tool registry.

## Requirements

- Flutter 3.24+ on the stable channel
- Dart 3.10.4+
- macOS 10.15+
- Xcode command line tools

## Development

```bash
flutter pub get
flutter run -d macos
```

## Verification

```bash
flutter analyze
flutter test
```

## Architecture

- `lib/registry/tool_registry.dart` registers all tools and drives sidebar ordering.
- `lib/state/tool_state.dart` stores selected tool, search query, and favorites with `ValueNotifier` plus `shared_preferences`.
- `lib/ui/main_shell.dart` and `lib/ui/sidebar.dart` provide the desktop shell and navigation.
- `lib/ui/widgets.dart` contains shared compact controls and editor panes.
- `lib/ui/tool_views.dart` currently contains the individual tool views and tool logic.

## Build

```bash
flutter build macos --release
```

The release app is written to `build/macos/Build/Products/Release/DevUtils.app`.
