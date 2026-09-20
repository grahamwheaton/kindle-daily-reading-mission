# Rupert's Reader launcher

This is the KDK 1.0/Java 1.4-compatible launcher for the Kindle 4 NoTouch.
Version 0.1 is intentionally a manually launched visual prototype: it owns the
screen, reads basic mission metadata when permitted, and handles D-pad focus.
The Kindle Home button remains an emergency escape.

The build uses clean-room compile-time Kindlet API stubs; Amazon's proprietary
SDK jar is not included. The shared MobileRead jailbreak developer keystore is
also not redistributed here. Point `build.ps1` at a compatible copy when
building.

The pinned `vendor/shairkindle` submodule supplies its MIT-licensed,
real-device-tested ixtab/MKK runtime permission gateway. Its compile-time
`ParseException` stub is never packaged; the patched MKK copy on the Kindle is
the actual gateway.

Do not enable auto-start or kiosk behaviour until the manually launched build
has been tested on the physical K4 and the Home escape has been confirmed.
