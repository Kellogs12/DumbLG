# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-12

### Added
- Initial fork of Clean Your TV customized specifically for LG webOS 4.5 (e.g. 65UM7400PTA, firmware 05.40.97).
- Pure Node 0.12 compatible supervisor service (`au.com.kellogs12.dumblg.service`) requiring no Python 3 or Node 8+ runtimes on TV.
- Native evdev input interceptor with ARM32 static `relay` binary targeting `/dev/input/event3` (Magic Remote) and `/dev/input/event1` (IR remote).
- Emergency exit gesture: triple-press Home within 2 seconds ungrabs input and falls back to stock LG Home without data loss.
- Live settings hook applying `livePlus: off`, `quickStartMode: off`, `homePromotion: off`, `homeAutoLaunch: off`, `screenSaverAd: off`, `adCookie: off`, `aiNudge: off` on boot via Luna Service2.
- Ad/ACR/Amazon telemetry blocklist via `/var/lib/webosbrew/init.d/50-dumblg-hosts`.
- Automatic streaming app debloat via `/var/lib/webosbrew/init.d/60-dumblg-removed-apps`.
- One-command SSH installer (`install.sh`) and uninstaller (`uninstall.sh`).
- Lightweight Python-based IPK packaging tool (`package-launcher.py`) without webOS CLI SDK dependencies.
- First signed release package: `au.com.kellogs12.dumblg.launcher_0.1.0_all.ipk`.
