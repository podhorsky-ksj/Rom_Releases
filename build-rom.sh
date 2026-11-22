#!/usr/bin/env bash

set -Eeuo pipefail

# Build a signed whyred ROM with MindTheGapps integrated into the system.
# Run from any directory; all paths are resolved relative to this script.
# Useful overrides:
#   BUILD_JOBS=7 BUILD_NICE=0 BUILD_IONICE_CLASS=2 ./build-rom.sh
#   BUILD_DATE=20261001 ./build-rom.sh
#   BUILD_EXTRA_TARGETS=libeventpolling_test ./build-rom.sh
#   BUILD_KEEP_UNSIGNED_TARGET=0 ./build-rom.sh  # Save packaging disk space.
#   BUILD_OTA_INPUT_TMPDIR=/tmp ./build-rom.sh  # Split OTA temporary storage.

ANDROID_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ANDROID_DIR"

BUILD_DATE="${BUILD_DATE:-$(date +%Y%m%d)}"
BUILD_JOBS="${BUILD_JOBS:-7}"
BUILD_NICE="${BUILD_NICE:-0}"
BUILD_IONICE_CLASS="${BUILD_IONICE_CLASS:-2}"
BUILD_KEEP_UNSIGNED_TARGET="${BUILD_KEEP_UNSIGNED_TARGET:-1}"
LINEAGE_VERSION="${LINEAGE_VERSION:-24.0}"
MINDTHEGAPPS_VERSION="${MINDTHEGAPPS_VERSION:-17.0.0-arm64-20261022_132445}"
PRODUCT="whyred"
LUNCH_TARGET="lineage_whyred-trunk_staging-userdebug"
PRODUCT_OUT="$ANDROID_DIR/out/target/product/$PRODUCT"
TMPDIR="${TMPDIR:-$ANDROID_DIR/out/ota-tmp-$BUILD_DATE}"
LOG="$ANDROID_DIR/out/whyred-no-adb-root-build-${BUILD_DATE}.log"
KEY_DIR="${KEY_DIR:-/home/ksj/.ssh/whyred-lineage-keys}"
MINDTHEGAPPS_ZIP="${MINDTHEGAPPS_ZIP:-$ANDROID_DIR/out/MindTheGapps-${MINDTHEGAPPS_VERSION}.zip}"
MINDTHEGAPPS_ROOT="${MINDTHEGAPPS_ROOT:-$ANDROID_DIR/out/mindthegapps-${MINDTHEGAPPS_VERSION}}"
MTG_APEX_NAME="com.google.android.gmssystem.prodvic"
MTG_APEX="$MINDTHEGAPPS_ROOT/system/product/apex/$MTG_APEX_NAME.apex"
MTG_MODULE_DIR="$ANDROID_DIR/vendor/ksj/mindthegapps"
MTG_STAGED_APEX="$MTG_MODULE_DIR/prebuilts/$MTG_APEX_NAME.apex"
MTG_GENERATED_BP="$MTG_MODULE_DIR/Android.bp"
MTG_PREBUILTS_DIR_CREATED=0
MTG_STAGED_APEX_CREATED=0
MTG_GENERATED_BP_CREATED=0
OTA_EXTRACTED_INPUT=""

UNSIGNED_TARGET="$PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/lineage_whyred-target_files.zip"
SIGNED_TARGET="$PRODUCT_OUT/lineage_whyred-target_files-signed-${BUILD_DATE}-no-adb-root-gapps.zip"
OTA="$PRODUCT_OUT/lineage-${LINEAGE_VERSION}-${BUILD_DATE}-UNOFFICIAL-whyred-signed.zip"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

on_exit() {
    local status=$?
    if [[ -n "$OTA_EXTRACTED_INPUT" && -d "$OTA_EXTRACTED_INPUT" && ! -L "$OTA_EXTRACTED_INPUT" ]]; then
        rm -r -- "$OTA_EXTRACTED_INPUT"
    fi
    if (( MTG_GENERATED_BP_CREATED )); then rm -f -- "$MTG_GENERATED_BP"; fi
    if (( MTG_STAGED_APEX_CREATED )); then rm -f -- "$MTG_STAGED_APEX"; fi
    if (( MTG_PREBUILTS_DIR_CREATED )); then rmdir -- "$MTG_MODULE_DIR/prebuilts" 2>/dev/null || true; fi
    if (( status == 0 )); then
        echo "[BUILD-DONE] $(date --iso-8601=seconds)"
    else
        echo "[BUILD-FAILED] status=$status $(date --iso-8601=seconds)" >&2
    fi
}
trap on_exit EXIT

command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v rg >/dev/null 2>&1 || fail "rg is required"
command -v nice >/dev/null 2>&1 || fail "nice is required"
command -v ionice >/dev/null 2>&1 || fail "ionice is required"

mkdir -p "$ANDROID_DIR/out" "$TMPDIR"
export TMPDIR
export MINDTHEGAPPS_ROOT

if [[ ! -f "$MTG_APEX" || \
      ! -f "$MINDTHEGAPPS_ROOT/system/product/priv-app/Phonesky/Phonesky.apk" ]]; then
    [[ -f "$MINDTHEGAPPS_ZIP" ]] || fail "MindTheGapps ZIP not found: $MINDTHEGAPPS_ZIP"
    echo "[PHASE] extracting MindTheGapps to $MINDTHEGAPPS_ROOT"
    mkdir -p "$MINDTHEGAPPS_ROOT"
    unzip -q "$MINDTHEGAPPS_ZIP" -d "$MINDTHEGAPPS_ROOT"
fi

[[ -f "$MTG_APEX" ]] || fail "$MTG_APEX_NAME APEX is missing from $MINDTHEGAPPS_ROOT"
[[ -f "$MINDTHEGAPPS_ROOT/system/product/priv-app/Phonesky/Phonesky.apk" ]] || \
    fail "Phonesky.apk is missing from $MINDTHEGAPPS_ROOT"
[[ -f "$MTG_MODULE_DIR/Android.bp.mtg-template" ]] || fail "MindTheGapps Android.bp template is missing"
for staged_file in "$MTG_STAGED_APEX" "$MTG_GENERATED_BP"; do
    [[ ! -e "$staged_file" && ! -L "$staged_file" ]] || \
        fail "MindTheGapps staging path already exists; refusing to overwrite: $staged_file"
done

if [[ ! -d "$MTG_MODULE_DIR/prebuilts" ]]; then MTG_PREBUILTS_DIR_CREATED=1; fi
mkdir -p "$MTG_MODULE_DIR/prebuilts"
MTG_STAGED_APEX_CREATED=1
cp --reflink=auto "$MTG_APEX" "$MTG_STAGED_APEX"
MTG_GENERATED_BP_CREATED=1
# Recreating an unchanged definition must not invalidate the whole Soong graph.
cp --preserve=timestamps "$MTG_MODULE_DIR/Android.bp.mtg-template" "$MTG_GENERATED_BP"

[[ -f "$KEY_DIR/releasekey.pk8" ]] || fail "releasekey.pk8 is missing from $KEY_DIR"
[[ -f "$KEY_DIR/releasekey.x509.pem" ]] || fail "releasekey.x509.pem is missing from $KEY_DIR"
exec > >(tee -a "$LOG") 2>&1

echo "[BUILD-START] $(date --iso-8601=seconds)"
echo "[CONFIG] source=$ANDROID_DIR"
echo "[CONFIG] lunch=$LUNCH_TARGET jobs=$BUILD_JOBS nice=$BUILD_NICE ionice-class=$BUILD_IONICE_CLASS"
echo "[CONFIG] MindTheGapps=$MINDTHEGAPPS_ROOT"
echo "[CONFIG] signing keys=$KEY_DIR"
echo "[CONFIG] ADB-root disabled; MindTheGapps integrated"

export TOP="$ANDROID_DIR"
set +u
source build/envsetup.sh
lunch "$LUNCH_TARGET"
set -u

echo "[PHASE] building target-files and otatools"
read -r -a extra_targets <<< "${BUILD_EXTRA_TARGETS:-}"
nice -n "$BUILD_NICE" ionice -c "$BUILD_IONICE_CLASS" \
    m -j"$BUILD_JOBS" target-files-package otatools "${extra_targets[@]}"

[[ -x "$ANDROID_DIR/out/host/linux-x86/bin/sign_target_files_apks" ]] || \
    fail "sign_target_files_apks was not produced by otatools"
[[ -x "$ANDROID_DIR/out/host/linux-x86/bin/ota_from_target_files" ]] || \
    fail "ota_from_target_files was not produced by otatools"

[[ -s "$UNSIGNED_TARGET" ]] || fail "target-files archive was not produced: $UNSIGNED_TARGET"

echo "[VERIFY] checking target-files for stale adb_root artifacts"
if unzip -Z1 "$UNSIGNED_TARGET" | rg -i '(^|/)adb_root(\.rc)?$' >/dev/null; then
    fail "stale adb_root artifact is present in target-files"
fi

echo "[PHASE] signing target-files with $KEY_DIR"
GAPPS_PRESERVE_ARGS=(
    -e GoogleCalendarSyncAdapter.apk=
    -e GoogleContactsSyncAdapter.apk=
    -e PrebuiltExchange3Google.apk=
    -e SpeechServicesByGoogle.apk=
    -e talkback.apk=
    -e GmsOverlay.apk=
    -e GmsSettingsOverlay.apk=
    -e GmsSettingsProviderOverlay.apk=
    -e GmsSetupWizardOverlay.apk=
    -e AndroidAutoStub.apk=
    -e FamilyLinkParentalControls.apk=
    -e GooglePartnerSetup.apk=
    -e GoogleRestore.apk=
    -e Phonesky.apk=
    -e Velvet.apk=
    -e VelvetTitan.apk=
    -e Wellbeing.apk=
    -e GoogleFeedback.apk=
    -e GoogleServicesFramework.apk=
    -e SetupWizard.apk=
)
out/host/linux-x86/bin/sign_target_files_apks -o -d "$KEY_DIR" \
    "${GAPPS_PRESERVE_ARGS[@]}" \
    "$UNSIGNED_TARGET" "$SIGNED_TARGET"

if [[ "$BUILD_KEEP_UNSIGNED_TARGET" == 0 ]]; then
    echo "[VERIFY] validating signed target-files before removing redundant unsigned archive"
    unzip -tq "$SIGNED_TARGET"
    [[ -s "$SIGNED_TARGET" && "$SIGNED_TARGET" != "$UNSIGNED_TARGET" ]] || \
        fail "refusing to remove unsigned input without a separate signed archive"
    rm -- "$UNSIGNED_TARGET"
    echo "[CLEANUP] removed redundant unsigned target-files; signed archive preserved"
fi

echo "[PHASE] generating signed OTA"
OTA_INPUT_ARGS=()
if [[ -n "${BUILD_OTA_INPUT_TMPDIR:-}" ]]; then
    [[ -d "$BUILD_OTA_INPUT_TMPDIR" ]] || fail 'OTA input temporary parent is missing'
    OTA_EXTRACTED_INPUT=$(mktemp -d "$BUILD_OTA_INPUT_TMPDIR/whyred-ota-input.XXXXXXXX")
    python3 - "$SIGNED_TARGET" "$OTA_EXTRACTED_INPUT" <<'PY'
import fnmatch, os, pathlib, shutil, stat, sys, zipfile
patterns = ['IMAGES/*', 'INSTALL/*', 'META/*', 'OTA/*', 'RADIO/*',
            '*/build.prop', '*/default.prop', '*/build.default', '*/etc/vintf/*',
            '*/etc/prop.default', 'RECOVERY/RAMDISK/system/etc/recovery.fstab',
            'RECOVERY/RAMDISK/etc/recovery.fstab']
destination = pathlib.Path(sys.argv[2]).resolve()
with zipfile.ZipFile(sys.argv[1]) as source:
    selected = [i for i in source.infolist()
                if any(fnmatch.fnmatchcase(i.filename, p) for p in patterns)]
    required = sum(i.file_size for i in selected)
    assert shutil.disk_usage(destination).free > required + 512 * 2**20
    for entry in selected:
        path = pathlib.PurePosixPath(entry.filename)
        assert not path.is_absolute() and '..' not in path.parts
        if stat.S_ISLNK(entry.external_attr >> 16):
            target = destination / entry.filename
            link = source.read(entry).decode('utf-8')
            assert not os.path.isabs(link)
            assert (target.parent / link).resolve().is_relative_to(destination)
            target.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(link, target)
        else:
            target = source.extract(entry, destination)
            mode = (entry.external_attr >> 16) & 0o777
            if mode:
                os.chmod(target, mode)
fstabs = [destination / ('RECOVERY/RAMDISK/' + p)
          for p in ('system/etc/recovery.fstab', 'etc/recovery.fstab')]
assert any(p.is_file() and any(len(line.split()) > 1 and line.split()[1] == '/boot'
           for line in p.read_text().splitlines()) for p in fstabs), 'Missing boot fstab entry'
print('Extracted OTA input including recovery fstab:', required, 'bytes')
PY
    OTA_INPUT_ARGS+=(--extracted_input_target_files "$OTA_EXTRACTED_INPUT")
fi
out/host/linux-x86/bin/ota_from_target_files -k "$KEY_DIR/releasekey" \
    "${OTA_INPUT_ARGS[@]}" "$SIGNED_TARGET" "$OTA"

echo "[VERIFY] validating archives"
unzip -tq "$SIGNED_TARGET"
unzip -tq "$OTA"
if unzip -Z1 "$OTA" | rg -i '(^|/)adb_root(\.rc)?$' >/dev/null; then
    fail "adb_root artifact is present in final OTA"
fi

for required_entry in \
    PRODUCT/apex/com.google.android.gmssystem.prodvic.apex \
    PRODUCT/priv-app/Phonesky/Phonesky.apk \
    SYSTEM_EXT/priv-app/GoogleServicesFramework/GoogleServicesFramework.apk; do
    if ! unzip -Z1 "$SIGNED_TARGET" | rg -Fx "$required_entry" >/dev/null; then
        fail "missing MindTheGapps entry in target-files: $required_entry"
    fi
done

sha256sum "$SIGNED_TARGET" "$OTA"
stat -c '%s bytes %y %n' "$SIGNED_TARGET" "$OTA"
