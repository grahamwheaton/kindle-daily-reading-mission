#!/usr/bin/env python3
"""Build and sign a device update, and write it into the content repository.

An update is one tar whose digest sits in a manifest signed by the offline
project key. The Kindle verifies the signature, checks the digest and installs
to destinations it decides itself, so this only has to say what goes in:

    runtime/   scripts that live in /usr/local/rupert
    documents/ files for the Kindle's documents folder
    state/     files for /mnt/us/rupert-mission
    plugin/    the KOReader plugin, replaced whole

The legacy three-file fields stay in the manifest so a device running the old
updater can still be updated: that is how a Kindle gets as far as the updater
that understands bundles.

Usage:
  publish-update.py --version 21 --key private/device-update-private.pem \\
                    --content ../rupert-reading-missions
"""

import argparse
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(staging, content):
    """Lay the update out the way the device expects to find it."""
    plan = {
        "runtime/sync.sh": PROJECT / "installer/rupert-sync.sh",
        "runtime/report.sh": PROJECT / "installer/rupert-report.sh",
        "runtime/device-update.sh": HERE / "device-update.sh",
        "state/open-current.sh": PROJECT / "launcher/open-current.sh",
        "state/sleep.png": PROJECT / "assets/sleep-screen.png",
    }
    # The launcher app is a build output, so it is not in the repository: fall
    # back to the copy already published, which is what the Kindle is running.
    launcher = PROJECT / "launcher/out/RupertsReader.azw2"
    if not launcher.is_file():
        launcher = content / "published/device/RupertsReader.azw2"
    if launcher.is_file():
        plan["documents/RupertsReader.azw2"] = launcher

    for source in sorted((PROJECT / "koreader/rupertdash.koplugin").glob("*.lua")):
        plan[f"plugin/{source.name}"] = source

    for target, source in plan.items():
        if not source.is_file():
            sys.exit(f"missing from the update: {source}")
        destination = staging / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    return plan


def build_tar(staging, out):
    # The old tar format: BusyBox 1.7.2 on the Kindle warns at PAX headers.
    with tarfile.open(out, "w", format=tarfile.USTAR_FORMAT) as archive:
        for path in sorted(staging.rglob("*")):
            if path.is_file():
                info = archive.gettarinfo(path, arcname=str(path.relative_to(staging)).replace("\\", "/"))
                info.mtime = 0          # so an unchanged update has an unchanged digest
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mode = 0o755
                with path.open("rb") as handle:
                    archive.addfile(info, handle)


def sign(manifest, signature, key):
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key), "-out", str(signature), str(manifest)],
        capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"signing failed: {result.stderr.strip()}")


def verify(manifest, signature, public_key):
    result = subprocess.run(
        ["openssl", "dgst", "-sha256", "-verify", str(public_key),
         "-signature", str(signature), str(manifest)],
        capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"the signature does not verify against the public key: {result.stdout.strip()}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True)
    parser.add_argument("--key", required=True, help="the offline signing key")
    parser.add_argument("--content", required=True, help="the content repository")
    args = parser.parse_args()

    key = pathlib.Path(args.key)
    if not key.is_file():
        sys.exit(f"no signing key at {key}")
    device = pathlib.Path(args.content) / "published/device"
    device.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as workspace:
        staging = pathlib.Path(workspace) / "bundle"
        staging.mkdir()
        plan = collect(staging, pathlib.Path(args.content))
        bundle = device / "bundle.tar"
        build_tar(staging, bundle)

        # The three files the old updater fetches by name, kept in step.
        for name, source in (("RupertsReader.azw2", plan.get("documents/RupertsReader.azw2")),
                             ("rupert-sync.sh", PROJECT / "installer/rupert-sync.sh"),
                             ("open-current.sh", PROJECT / "launcher/open-current.sh")):
            if source and source.is_file():
                shutil.copyfile(source, device / name)

        manifest = device / "manifest.txt"
        lines = [f"version={args.version}", f"bundle_sha256={digest(bundle)}"]
        for field, name in (("launcher_sha256", "RupertsReader.azw2"),
                            ("sync_sha256", "rupert-sync.sh"),
                            ("open_current_sha256", "open-current.sh")):
            path = device / name
            if path.is_file():
                lines.append(f"{field}={digest(path)}")
        manifest.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

        signature = device / "manifest.sig"
        sign(manifest, signature, key)
        verify(manifest, signature, HERE / "device-update-public.pem")

    print(f"signed device update {args.version}")
    print(f"  bundle:  {bundle.stat().st_size} bytes, {len(plan)} files")
    for target in sorted(plan):
        print(f"    {target}")


if __name__ == "__main__":
    main()
