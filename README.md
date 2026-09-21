# Kindle Daily Reading Mission

An experimental system that publishes a short daily MOBI book to GitHub and
lets a jailbroken Kindle 4 retrieve it directly over Wi-Fi. It was built for a
Kindle 4 NoTouch Silver (K4S/D01100) running firmware 4.1.4.

**Do not install these scripts on another Kindle model or firmware without
reviewing and adapting them.** The installer writes a small, isolated runtime
under `/usr/local/rupert` and adds one marked root-cron entry. A recovery plan
and USB-visible backup should exist before modifying a Kindle.

This repository contains the original-device notes, diagnostic scripts,
reversible installer scripts, Kindle-side synchronizer, and an optional Windows
USB fallback. It deliberately excludes private keys, firmware, device backups,
generated books, third-party packages, and downloaded executables.

## Current phase

Phases 1 and 2 are complete: the illustrated MOBI works on the physical Kindle,
and the Kindle now retrieves published missions directly from GitHub over
Wi-Fi. USB transfer remains a recovery fallback.

## Delivery flow

1. A scheduled Codex task generates a roughly five-minute illustrated story and
   converts it to legacy MOBI 6 with Calibre.
2. It publishes `published/today.mobi` and `published/date.txt` to a separate
   content repository.
3. `installer/rupert-sync.sh` checks that mission ID every five minutes while
   the Kindle is awake.
4. When the ID changes, the Kindle performs a certificate-validated TLS 1.2
   download and atomically replaces `Today's Reading Mission.mobi`.

The Kindle's clock is not trusted for freshness; the published ID is the source
of truth.

## Requirements and provenance

- Confirmed hardware: K4S/D01100, serial prefix B00E, firmware 4.1.4.
- NiLuJe Kindle 4 jailbreak 1.8.N and USBNetwork 0.57.N were used during
  development. Those third-party packages are not redistributed here.
- The modern downloader tested on-device is the ARM EABI5 soft-float curl
  7.83.1/wolfSSL 5.3.0 build from `llamasoft/static-cross-bins` release v1.0.1.
  Its binary SHA-256 is
  `B4BA11023F859878E44BDCB15B1CE5D5EBF5D256D8F01E447834EC809EB68726`.
- The CA bundle is obtained from `https://curl.se/ca/cacert.pem`; the copy used
  in the initial installation had SHA-256
  `F66DFF1BDF8F96060B8177976F8B7D9254BC89BC4DB933D769F7384D28480BC9`.
- Stage those two files as `/mnt/us/rupert-stage/curl` and
  `/mnt/us/rupert-stage/cacert.pem` before using the downloader test installer.

See `DEVICE_NOTES.md` for the exact tested history and recovery boundaries.

## Test mission

`missions/001-mud-runner-rescue/mission.html` is the reflowable source. The
planned device file is MOBI, because firmware 4.1.4 can read it natively with
adjustable fonts and normal page turns. PDF is not the primary test format
because its fixed page layout makes font adjustment poor on a 6-inch screen.

## USB delivery

With the Kindle connected in normal USB storage mode, deliver a prepared MOBI:

```powershell
.\kindle_daily_mission\deliver-to-kindle.ps1 -MissionPath ".\path\mission.mobi"
```

The helper finds the Kindle, writes through a temporary file, verifies SHA-256,
and then replaces `documents/Today's Reading Mission.mobi`. The Kindle refreshes
its library after it is safely ejected and disconnected.

## Daily mission log

| Date | Title | Type | Output | Delivery |
| --- | --- | --- | --- | --- |
| 2026-09-21 | *Rupert and Tom's Trail Map* | Fiction | `missions/2026-09-21-rupert-and-toms-trail-map/Rupert and Tom's Trail Map.mobi` | Published to GitHub for Kindle Wi-Fi delivery |
| 2026-09-20 | *The Mud Runner Rescue* | Fiction | `missions/001-mud-runner-rescue/The Mud Runner Rescue.mobi` | Published to GitHub and fetched independently by Kindle Wi-Fi |

## Automatic Wi-Fi delivery

- The 16:30 Codex task generates and converts the mission, then publishes
  `published/today.mobi` and `published/date.txt` in the separate public
  `grahamwheaton/rupert-reading-missions` repository.
- While awake, the Kindle checks the published mission ID every five minutes.
  It downloads only when that ID changes, using certificate-validated HTTPS.
- The current mission appears as `documents/Today's Reading Mission.mobi`.
- The Kindle clock is not used to decide whether a mission is new.
- Runtime state and logs are under `/mnt/us/rupert-mission`; the isolated
  downloader, certificate bundle, and sync script are under
  `/usr/local/rupert`.
- The original root crontab is backed up as
  `/mnt/us/rupert-mission/root-crontab.original`.
