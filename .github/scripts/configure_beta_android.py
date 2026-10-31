#!/usr/bin/env python3
"""Validate the maintained Android integration in a generated Flutter runner.

The filename is retained for workflow compatibility. This script intentionally
does not overwrite MainActivity.kt or synthesize a second screen-capture
service: app/native_android is the single source of truth for these components.
"""

from pathlib import Path
import shutil

android = Path("android")
main_candidates = list((android / "app/src/main/kotlin").rglob("MainActivity.kt"))
if len(main_candidates) != 1:
    raise SystemExit(
        f"Expected exactly one generated MainActivity.kt, found {len(main_candidates)}"
    )

main_activity = main_candidates[0]
main_text = main_activity.read_text()
manifest_path = android / "app/src/main/AndroidManifest.xml"
if not manifest_path.is_file():
    raise SystemExit("Generated AndroidManifest.xml is missing")
manifest = manifest_path.read_text()

required_channels = (
    "com.snote/alarm_audio",
    "com.snote/screen_capture",
)
for channel in required_channels:
    if channel not in main_text:
        raise SystemExit(f"Maintained MainActivity is missing MethodChannel {channel!r}")

# Copy maintained launch resources over Flutter's generated defaults so the
# native splash is the only startup surface shown before the first Flutter frame.
source_resources = Path("app/native_android/res")
target_resources = android / "app/src/main/res"
if source_resources.is_dir():
    for source in source_resources.rglob("*"):
        if not source.is_file():
            continue
        target = target_resources / source.relative_to(source_resources)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

for required_resource in (
    target_resources / "values/styles.xml",
    target_resources / "drawable/launch_background.xml",
    target_resources / "values-v31/styles.xml",
):
    if not required_resource.is_file():
        raise SystemExit(f"Maintained Android launch resource was not copied: {required_resource}")

source_dir = main_activity.parent
for source_name in ("ScreenCaptureBridge.kt", "ScreenCaptureService.kt"):
    if not (source_dir / source_name).is_file():
        raise SystemExit(f"Maintained Android source {source_name} was not copied")

required_manifest_tokens = (
    'android:name=".ScreenCaptureService"',
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
    "android.permission.CAMERA",
    "android.permission.POST_NOTIFICATIONS",
    'android:mimeType="application/pdf"',
)
for token in required_manifest_tokens:
    if token not in manifest:
        raise SystemExit(f"Maintained Android manifest is missing {token!r}")

if "SnoteScreenCaptureService" in manifest:
    raise SystemExit(
        "Duplicate SnoteScreenCaptureService detected; use the maintained "
        ".ScreenCaptureService declaration only"
    )

print(
    "Validated maintained Android integration: ringtone and screen-capture "
    "channels, capture bridge/service, and required manifest permissions."
)
