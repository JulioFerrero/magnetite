# Launcher

A Raycast 2–looking app launcher that does one thing: search and open apps.
Native AppKit + Liquid Glass (macOS 26+), no dependencies, ~1,250 lines of Swift.
Bundles the Inter font (SIL Open Font License, see `Resources/Fonts/LICENSE.txt`), trimmed to what the UI uses by `scripts/make-font.sh` from the original in `Resources/Fonts/source/`.

## Build & install

```sh
./build.sh install   # builds, copies to /Applications, starts it
```

It adds itself to Login Items on first run (turn it off in System Settings → General → Login Items if you want).

## Use

| Key | Does |
|---|---|
| ⌘Space | show / hide |
| type | filter apps (prefix, word starts, initials like `vsc`, fuzzy) |
| ↑ ↓ / ⌃N ⌃P / ⌃J ⌃K | move |
| ↩ | open |
| ⌘↩ | show in Finder |
| ⌘K | actions (open, show in Finder, settings, quit) |
| ⌘, | settings |
| Esc | clear the query, then close |
| ⌘Q | quit Launcher |

Apps you open often float to the top, and it remembers what you picked for a query.
It indexes `/Applications`, `/System/Applications`, `~/Applications` and a few system folders each time it opens, so new apps show up immediately.

## Settings

⌘, (or Actions ⌘K → Settings…) opens Settings:

- **Shortcut**: click it and press a new combination; it takes effect immediately.
- **Theme**: Raycast (tinted Liquid Glass + shadow), Glass (clear Liquid Glass with a sliding glass selection) or Performance (solid, no blur, no shadow).

## Look

All sizes and colors live in `Sources/Theme.swift`.
