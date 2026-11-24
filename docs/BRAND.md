# Paigham brand guide

<img src="../app/assets/brand/logo.png" width="96">

## Name

**Paigham · پیغام** means *message* in both Pashto and Dari, so every Afghan reads it the same way. The Latin spelling is used for app stores and file names.

The name is a working name. To change it, edit `app/lib/brand/brand.dart` (`nameLatin`, `nameNative`), the `app_name` string in `app/lib/l10n/strings.dart`, and the platform labels (Android `res/values*/strings.xml`, iOS `Info.plist`, macOS `AppInfo.xcconfig`, Windows `Runner.rc`, web `index.html` + `manifest.json`).

## Story

- **Lapis lazuli blue**: the deep blue stone mined in Badakhshan for 6,000 years. Our main colour.
- **Saffron gold**: Herat saffron. Used for actions (send button, new chat), unread badges and read ticks.
- **Eight-pointed star**: the geometric star of Afghan tile work, from the Blue Mosque in Mazar to the Herat Friday Mosque. It sits inside the speech bubble in the logo and forms the chat wallpaper.

The palette deliberately avoids flag colours so the app stays neutral for every Afghan.

## Colours

| Token | Hex | Use |
|---|---|---|
| Lapis | `#1F3F9E` | App bar, primary buttons, logo tile |
| Lapis deep | `#142A6B` | Gradients, dark accents |
| Lapis bright | `#3D63D6` | Gradient highlight |
| Lapis mist | `#E6ECFA` | Selected items, outgoing bubble tint |
| Saffron | `#F2A516` | Send button, FAB, unread badges |
| Saffron deep | `#D98A00` | Read ticks, highlighted times |
| Pomegranate | `#C6303E` | Errors, delete |
| Turquoise | `#1E8C6E` | Prayer times, bot avatar |
| Ink | `#141A2E` | Text |
| Paper | `#F5F7FC` | Light background |
| Night | `#0C1222` | Dark background |

## Type

**Vazirmatn** (SIL Open Font License), bundled with the app so Pashto letters such as ښ ږ ځ څ ټ ډ ړ ګ ې ۍ always render correctly, even offline. Numbers are shown in Eastern Arabic-Indic digits (۰۱۲۳…) in Pashto and Dari.

## Logo files

| File | Use |
|---|---|
| `app/assets/brand/logo.svg` / `.png` | Rounded tile, general use |
| `app/assets/brand/icon_square.png` | iOS / Android legacy icon (full bleed) |
| `app/assets/brand/icon_foreground.png` | Android adaptive icon foreground |
| `app/assets/brand/icon_macos.png` | macOS icon with standard padding |
| `app/assets/brand/mark.svg` | Mark only, lapis on transparent |

Regenerate all platform icons after changing them: `cd app && dart run flutter_launcher_icons`.
