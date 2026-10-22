#!/usr/bin/env python3
"""Validate ios/Runner/Info.plist.

`plutil -lint` is macOS-only, so on a non-macOS host we substitute two
equivalent checks:

1. XML well-formedness (plist files are XML) via `xml.etree.ElementTree`.
2. A real plist parse via `plistlib.load`, which is the same parser Apple's
   `plutil` uses for the XML plist format.

Then assert the permission / background-mode contract the app depends on.
"""

from __future__ import annotations

import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PLIST = Path(__file__).resolve().parent.parent / "ios" / "Runner" / "Info.plist"

# key -> expected type
REQUIRED_SCALARS: dict[str, type] = {
    "NSLocationWhenInUseUsageDescription": str,
    "NSLocationAlwaysAndWhenInUseUsageDescription": str,
    "NSLocationAlwaysUsageDescription": str,
    "NSFaceIDUsageDescription": str,
    "NSMotionUsageDescription": str,
    "LSSupportsOpeningDocumentsInPlace": bool,
    "UIFileSharingEnabled": bool,
    "BGTaskSchedulerPermittedIdentifiers": list,
}

REQUIRED_BACKGROUND_MODES = {"location", "processing"}

# The BGTaskScheduler identifier workmanager actually registers:
#   lib/src/services/background_sync_scheduler.dart -> AppConfig.backgroundSyncUniqueName
#   -> workmanager_apple: schedulePeriodicTask(taskIdentifier: request.uniqueName)
#   -> BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier)
PERMITTED_TASK_IDENTIFIERS = {"routenote.periodicSync"}


def fail(message: str) -> None:
    print(f"FAIL  {message}")
    sys.exit(1)


def main() -> int:
    if not PLIST.exists():
        fail(f"{PLIST} does not exist")

    raw = PLIST.read_bytes()

    # 1. XML well-formedness (plutil -lint's XML stage).
    try:
        ET.fromstring(raw)
    except ET.ParseError as exc:
        fail(f"XML is not well-formed: {exc}")
    print("OK    XML is well-formed")

    # 2. Real plist parse (plutil -lint's semantic stage).
    try:
        with PLIST.open("rb") as handle:
            data = plistlib.load(handle)
    except Exception as exc:  # noqa: BLE001 - plistlib raises several types
        fail(f"plistlib could not parse the file: {exc}")
    print("OK    plistlib parsed the file")

    if not isinstance(data, dict):
        fail("root plist object is not a dictionary")
    print("OK    root object is a dictionary")

    # 3. Required keys.
    for key, expected_type in REQUIRED_SCALARS.items():
        if key not in data:
            fail(f"missing key: {key}")
        value = data[key]
        if expected_type is bool:
            if not isinstance(value, bool):
                fail(f"{key} must be a boolean, got {type(value).__name__}")
        elif not isinstance(value, expected_type):
            fail(f"{key} must be {expected_type.__name__}, got {type(value).__name__}")
        if isinstance(value, str) and not value.strip():
            fail(f"{key} is empty")
    print(f"OK    all {len(REQUIRED_SCALARS)} required keys present and typed")

    # 4. Background modes.
    modes = data.get("UIBackgroundModes")
    if not isinstance(modes, list):
        fail("UIBackgroundModes is missing or not an array")
    missing = REQUIRED_BACKGROUND_MODES - set(modes)
    if missing:
        fail(f"UIBackgroundModes is missing: {sorted(missing)}")
    print(f"OK    UIBackgroundModes contains {sorted(REQUIRED_BACKGROUND_MODES)}")

    # 5. Every permitted identifier is unique and non-empty.
    permitted = data["BGTaskSchedulerPermittedIdentifiers"]
    if not permitted:
        fail("BGTaskSchedulerPermittedIdentifiers is empty")
    if len(permitted) != len(set(permitted)):
        fail("BGTaskSchedulerPermittedIdentifiers contains duplicates")
    if not PERMITTED_TASK_IDENTIFIERS.issubset(set(permitted)):
        fail(
            "BGTaskSchedulerPermittedIdentifiers does not cover the identifier "
            f"workmanager registers ({sorted(PERMITTED_TASK_IDENTIFIERS)})"
        )
    print(f"OK    BGTaskSchedulerPermittedIdentifiers covers {sorted(PERMITTED_TASK_IDENTIFIERS)}")

    # 6. `processing` requires permitted identifiers (Apple rejects otherwise).
    if "processing" in modes and not permitted:
        fail("UIBackgroundModes declares 'processing' but no permitted identifiers")

    print("\nAll Info.plist checks passed.")
    print(f"  file       : {PLIST}")
    print(f"  bytes      : {len(raw)}")
    print(f"  modes      : {modes}")
    print(f"  permitted  : {permitted}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
