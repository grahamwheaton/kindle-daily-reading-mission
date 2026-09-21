# Device and recovery notes

## Identification status

- Reported firmware: `4.1.4 (3543630001)`.
- Confirmed USB serial prefix: `B00E` (the full serial is deliberately not
  stored in the project notes).
- Exact model: **Kindle 4 NoTouch Silver (2011), K4S**, model family D01100.
- Firmware `4.1.4 (3543630001)` is the expected final Amazon firmware for this
  hardware family.
- USB identity: Amazon VID `1949`, PID `0004`; Windows exposes it as `Kindle
  Internal Storage` on a FAT32 volume labelled `Kindle`.
- Capacity observed: 1,456,070,656 bytes, with 1,184,628,736 bytes free before
  the Phase 1 transfer.

## Backup

- Created `backups/2026-09-20-pre-phase1-usb` before writing to the Kindle.
- Copied 558 files totalling 267,759,693 bytes, excluding only Windows'
  `System Volume Information` folder.
- `backup-summary.json` records the source and totals.
- `sha256-manifest.csv` contains a checksum, byte length, and relative path for
  all 558 copied Kindle files.

## Phase 1 transfers

- Copied `The Mud Runner Rescue.txt` to `documents/` as the lowest-risk first
  sideload test.
- Verified the device copy byte-for-byte with SHA-256
  `F68BFA11A2B3225BB884E773E4E47DA52E26CDC6CCD15A27158CF9EB9B614333`.
- TXT tests native library discovery, normal page turning, and adjustable font
  sizes. It cannot contain the illustration or rich title metadata, so MOBI is
  still the intended final Phase 1 format.
- Rupert successfully opened and read the TXT test on the physical Kindle.
- Installed the signed official Calibre 9.15.0 portable build at
  `C:\Users\Grayw\Documents\BeaverLand\Calibre Portable`. The portable
  installer requires the final destination to be shorter than 59 characters.
- Converted `mission.html` to legacy MOBI 6 using the `kindle` output profile
  and copied it to `documents/The Mud Runner Rescue.mobi`.
- Verified MOBI SHA-256:
  `1CAF85959FF25A9C720EC4ECEC827E11D1FF3951AA1FAB0002D551F37EB0FD9E`.

## Recovery plan

1. Record serial number/prefix, model marking, registration state, firmware,
   free space, and visible root directory structure.
2. Make a dated copy of all user-visible USB storage on the PC and verify file
   counts and hashes.
3. Keep the official Amazon 4.1.4 package reference for the confirmed K4/K4B,
   but do not reinstall firmware merely as a test.
4. Before jailbreak work, archive the exact jailbreak package and its README,
   verify its checksum/source, and document uninstall steps.
5. Preserve a charged battery and a known-good USB cable. Never interrupt an
   update. If the device fails to boot, stop before low-level flashing; serial
   recovery and raw partition writes carry materially higher brick risk.

## Phase 2 delivery decision

- Amazon ended downloads to Kindle devices released in 2012 or earlier on
  2026-05-20. Native delivery therefore cannot be the dependable daily path
  for this 2011 K4S.
- USB sideloading works but requires connecting and ejecting the cable every
  day, so it remains the recovery/manual fallback.
- The selected automation is direct, certificate-validated HTTPS delivery from
  GitHub. The PC does not need to be connected to the Kindle during normal use.

## Installed jailbreak and USBNetwork

- NiLuJe K4 jailbreak 1.8.N was installed successfully using the documented K4
  diagnostics procedure. The Kindle returned to normal operation.
- NiLuJe USBNetwork 0.57.N for K4 was installed successfully.
- A dedicated RSA key was placed in `usbnet/etc/authorized_keys`; its private
  key is kept in the ignored `private/` directory on this PC.
- Wi-Fi-only SSH was configured with `K3_WIFI=true`,
  `K3_WIFI_SSHD_ONLY=true`, Dropbear, and the required K4 `USE_VOLUMD=true`.
- The Kindle joins the home Wi-Fi and the router identifies it, but USBNetwork
  0.57.N starts and then reports `usbnet is already stopped`; port 22 never
  becomes reachable. Automatic and verbose startup markers were removed again,
  along with the stale PID marker, so normal boot remains clean.
- USBNetwork remains installed for recovery experiments but is not used by the
  daily delivery system. Its automatic startup markers are absent.

## Installed direct-delivery system

- A statically linked ARM EABI5 curl 7.83.1 with wolfSSL 5.3.0 is installed at
  `/usr/local/rupert/curl`; it does not replace Amazon's curl 7.21.4.
- A current Mozilla-derived CA bundle is installed at
  `/usr/local/rupert/cacert.pem`. Downloads require HTTPS, TLS 1.2, normal
  certificate validation, HTTP success, and a minimum MOBI size of 1 KiB.
- `/usr/local/rupert/sync.sh` runs from a uniquely marked entry in
  `/etc/crontab/root` every five minutes while the Kindle is awake.
- The sync compares GitHub's `published/date.txt` with
  `/mnt/us/rupert-mission/last-remote-id`; it downloads `published/today.mobi`
  only when the ID changes and replaces the document atomically.
- The original crontab is preserved at
  `/mnt/us/rupert-mission/root-crontab.original`.
- The first live test succeeded over Wi-Fi and the downloaded MOBI SHA-256
  matched the published file:
  `1CAF85959FF25A9C720EC4ECEC827E11D1FF3951AA1FAB0002D551F37EB0FD9E`.
- Uninstall source is `installer/runme-uninstall-scheduler.sh`. It removes the
  marked scheduler entry and sync script; the downloader can be retained for
  recovery or removed separately after confirming nothing else uses it.

## Launcher and KOReader (2026-09-21)

- `RupertsReader.azw2` is KUAL, with `KualKindlet` patched so that on start it
  runs `/mnt/us/rupert-mission/open-current.sh`. It does not show a menu.
- Firmware 4.1.4 cannot open a document by path over lipc. The only
  `com.lab126.framework` commands are `read`, `insertKeystroke`,
  `dismissDialog` and `clearRffItems`. `read 1` is accepted, but the framework
  returns to Home.
- KOReader `kindle-legacy` v2026.07.1 (zip SHA-256
  `0ED8D5EEC422DAD4894DDC426894C260CCE55EC3EE3C0BE9E8A4FE46C45A5CDE`) was
  copied by hand to `/mnt/us/koreader` and `/mnt/us/extensions/koreader`.
  From update v16, `open-current.sh` starts it with the mission file, so one
  tap from Home opens the book.
- BusyBox is v1.7.2. It has no `nohup` and no `grep -E`.
- While KOReader is running, Windows sees the USB storage as an empty drive.
  Exit KOReader (Menu, last tab, Exit) before connecting the cable.

## SSH over Wi-Fi via KOReader

- KOReader's own Dropbear works where USBNetwork's did not. Start it from
  Menu, then the network tab, then SSH server (port 2222, key login only, root).
  It runs only while KOReader is open and the Kindle is awake.
- `koreader/settings/SSH/authorized_keys` holds `rupert_kindle_rsa.pub`
  (fingerprint `SHA256:Au/VcFoFMpOjATaE9EuVPctdtJyxaukgbY/Ts0cogDg`).

## Sync fixes (update v17)

- The wake listener's PID file lived on `/mnt/us`, which is unmounted in USB
  mode. Every cron run during a USB session started another listener; 14 had
  accumulated. The PID file is now on tmpfs, strays are stopped, and
  `sync.sh` exits in USB mode.
- A running `sync.sh` held its own file open. When the updater replaced it,
  `mntroot ro` failed with `mount: / is busy`, leaving the root filesystem
  writable. `sync.sh` now runs from a self-deleting `/var/tmp` copy.
- Wi-Fi is switched back off after a check if it was off beforehand.
  `sync.log` is trimmed at 64 KiB, the archive keeps 14 missions, and Kindlet
  log snapshots run only when `/mnt/us/rupert-mission/debug` exists.

## Jailbreak preparation

- Selected package: MobileRead/NiLuJe `kindle-k4-jailbreak-1.8.N.zip`.
- Package source: attachment 141180 from MobileRead thread 191158.
- Archive SHA-256:
  `E83DA520A25B0186433F50D93E80AF7245FBDF2BC2FB3593E25C2C01DDEC9C52`.
- Package README inspected in full. It is designed for Kindle 4, installs one
  developer key without replacing existing files, includes an uninstaller,
  and uses the documented K4 diagnostics boot path.
- Installation files are staged only in `research/jailbreak-1.8.N`; none have
  been copied to the Kindle yet.

## Recovery assets and decision points

- USB-visible storage backup is complete and checksummed (see Backup above).
- Official Amazon K4/K4B 4.1.4 update cached at
  `recovery/Update_2692310002-3543630001.bin`.
- Official-update SHA-256:
  `D2E0F5E1ECBBDB1077F8AF931F4502A80125195317B7C3FD2741D926AA84CE5A`.
- Normal diagnostics exit: `D) Exit, Reboot or Disable Diags`, then `R) Reboot
  System`, then `Q) To continue` using the 5-way controller.
- If the UI freezes during a reboot, wait several minutes before a long power
  restart; e-ink commonly retains a stale image while the system reboots.
- If the device cannot leave diagnostics or boot normally, stop before any raw
  partition write. The documented last-resort recovery is the MobileRead
  Kubrick LiveUSB/LiveCD for Kindle 4; preparing and using it is a separate,
  higher-risk recovery operation.

## Sources checked

- Amazon: Previous Software Updates for Kindle E-Reader (4th/5th generation).
- MobileRead Wiki: Kindle Serial Numbers.
- MobileRead Wiki: Kindle4NTHacking (states support for 4.0.0 through 4.1.4).
- KindleModding: manually downloading firmware update files.

URLs and a final, package-specific procedure will be recorded after the serial
prefix confirms the exact revision.
