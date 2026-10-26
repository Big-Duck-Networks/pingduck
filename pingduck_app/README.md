# PingDuck Mobile App

The cross-platform Flutter mobile client for PingDuck network discovery and monitoring, backed by the C++ engine (`pingduck-core`) via Dart FFI.

## Structure

```text
lib/
├── core/
│   ├── bridge/         # Dart FFI bindings to pingduck-core
│   ├── constants/      # AppVersion, AppFlavor
│   ├── theme/          # PingDuckColors, typography, components
│   └── widgets/        # DuckLogo, PdPanel, PdButton, PdChip, etc.
└── features/
    ├── account/        # Supabase auth, user profile, about panel
    ├── agent/          # Homelab Agent pairing and monitoring
    ├── billing/        # RevenueCat purchases & paywall
    ├── networks/       # Network ledger & subnet history
    ├── onboarding/     # First-time permissions & intro flow
    ├── scanner/        # Radar scope, device list, discovery state
    └── shell/          # Navigation shell, bottom bar, app bar
```

## Flavors

PingDuck defines two application flavors:

| Flavor | Application ID | Label | Accent & Mark |
| ------ | -------------- | ----- | ------------- |
| `dev` | `app.webcap.pingduck.dev` | `PingDuck Dev` | Amber duck (`#D97706`), Emerald beak/badge |
| `prod` | `app.webcap.pingduck` | `PingDuck` | Canonical Emerald duck (`#059669`), Amber beak |

Both flavors can be installed simultaneously on the same device without conflicting.

## Running Locally

```sh
# Run development flavor
flutter run --flavor dev -t lib/main.dart

# Run production flavor
flutter run --flavor prod -t lib/main.dart
```

## Testing & Quality Checks

Before committing or pushing changes:

```sh
# Static analysis (zero warnings/errors expected)
flutter analyze

# Unit and widget test suite
flutter test
```

## Branding & Assets Pipeline

App icons and splash screens are generated from vector math in `tool/make_brand_assets.py`:

```sh
# 1. Render raster assets from vector geometry
uv run --with pillow python tool/make_brand_assets.py

# 2. Update Android/iOS app launcher icons (prod + dev)
dart run flutter_launcher_icons && dart run flutter_launcher_icons:main -f flutter_launcher_icons-dev.yaml

# 3. Update Android/iOS native splash screens (prod + dev)
dart run flutter_native_splash:create -F dev,prod
```
