# DumbLG

A fast, lightweight custom home launcher and telemetry/ad blocker for older LG webOS 4.5 TVs (e.g. 65UM7400PTA, webOS 4.5, firmware 05.40.97, Node.js 0.12.2 on-TV, Python 2.7).

Forked from [Razdva122/clean-your-tv-lg-webos](https://github.com/Razdva122/clean-your-tv-lg-webos) with inspiration from [lasharor/cleanyourtv-WebOS](https://github.com/lasharor/cleanyourtv-WebOS) and [humblemuzzu/dumbtv](https://github.com/humblemuzzu/dumbtv).

---

## Highlights

- **Replaces LG Home Screen**: Seamlessly redirects the remote HOME button to the lightweight DumbLG launcher (`au.com.kellogs12.dumblg.launcher`).
- **Node 0.12 Compatible**: Designed specifically for webOS 4.5 devices that ship with Node v0.12.2 and Python 2.7 (does not require Node 8+ or Python 3.9 on-device).
- **Evdev Hardware Input Grab**: Uses an ARM32 static `relay` supervisor that hooks `/dev/input/event3` (Magic Remote) and `/dev/input/event1` (IR Remote) for instantaneous Home button interception.
- **Emergency Exit**: Triple-press Home within 2 seconds instantly ungrabs input and restores the stock LG Home screen without losing any user configuration.
- **Live-Settings Hook**: Re-applies privacy and performance settings on every boot via Luna Service2 bus calls (`livePlus: off`, `quickStartMode: off`, `homePromotion: off`, `homeAutoLaunch: off`, `screenSaverAd: off`, `adCookie: off`, `aiNudge: off`).
- **Telemetry & Ad Blocking**: Bundled `50-dumblg-hosts` init.d hook bind-mounts `/etc/hosts` and blocks 11 known LG ad/ACR and Amazon telemetry domains.
- **Streaming Bloatware Removal**: Bundled `60-dumblg-removed-apps` init.d hook sweeps and uninstalls 10 preinstalled streaming applications on boot and 60 seconds post-boot.
- **One-Command Install & Uninstall**: Full automated setup over SSH without requiring webOS SDK CLI or desktop wizards.

---

## Target Device Prerequisites

- Rooted webOS TV (e.g. via [faultmanager-autoroot](https://github.com/throwaway96/faultmanager-autoroot)).
- [webOS Homebrew Channel](https://github.com/webosbrew/webos-homebrew-channel) installed.
- SSH key authentication enabled on port 22 as root (e.g. configured in SSH config as host `labfam`).

---

## Quick Start

### Installation

From your dev machine (Mac/Linux):
```bash
git clone https://github.com/Kellogs12/DumbLG.git
cd DumbLG
./install.sh labfam
```

Or execute directly on the TV over SSH:
```bash
ssh labfam 'cd /home/root/dumblg-install && sh install.sh --on-tv'
```

The installer will:
1. Back up existing configuration to `/home/root/dumbtv-webos-backup/`.
2. Build and install the launcher IPK to `/media/developer/apps/usr/palm/applications/`.
3. Install and elevate the background supervisor service (`au.com.kellogs12.dumblg.service`).
4. Register Luna Service2 permissions, roles, and manifests.
5. Install boot hooks into `/var/lib/webosbrew/init.d/`:
   - `50-dumblg-hosts`
   - `60-dumblg-removed-apps`
   - `70-dumblg-service`
   - `dumblg-uninstall`
6. Apply live settings and start DumbLG Home immediately.

---

## Uninstallation

To cleanly restore the TV to stock state at any time:

```bash
ssh labfam 'sh /var/lib/webosbrew/init.d/dumblg-uninstall'
```

Or from your computer:
```bash
./uninstall.sh labfam
```

This terminates the supervisor service, removes all init.d hooks and Luna registrations, cleans up application files, restores the stock LG Home screen, and preserves all user backups in `/home/root/dumbtv-webos-backup/`.

---

## Project Structure

- `/launcher/` — Clean webOS Home launcher UI (HTML/CSS/JS, ARM32 safe, card window mode).
- `/service/` — Pure Node 0.12 background supervisor service (`service.js`) and static ARM32 `bin/relay` input grabber.
- `/package-launcher.py` — Standalone, dependency-free script to build standard webOS `.ipk` packages using Python standard library.
- `/install.sh` — One-command installer (runs from host over SSH or locally on TV).
- `/uninstall.sh` — One-command uninstaller and emergency rollback script.
- `/CHANGELOG.md` — Release history and notes.

---

## Emergency Exit

If you ever need stock LG Home without uninstalling DumbLG:
- **Press the HOME button 3 times within 2 seconds**.
- The relay releases the input grab and sets the emergency latch.
- Stock LG Home opens immediately.
- To re-enable DumbLG later:
  ```bash
  ssh labfam "luna-send -n 1 -a com.webos.service.secondscreen.gateway luna://au.com.kellogs12.dumblg.service/resetEmergency '{}'"
  ```

---

## Inspiration & Acknowledgements

- [Clean Your TV (Razdva122)](https://github.com/Razdva122/clean-your-tv-lg-webos) — Upstream base for the custom launcher UI and evdev relay implementation.
- [Clean Your TV Root Edition (lasharor)](https://github.com/lasharor/cleanyourtv-WebOS) — Scope and architecture inspiration for all-in-one debloat and adblocking.
- [dumbtv (humblemuzzu)](https://github.com/humblemuzzu/dumbtv) — Lightweight debloat philosophy and hosts blocking approach.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
