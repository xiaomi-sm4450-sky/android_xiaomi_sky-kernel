#!/bin/bash
#
# Copyright (C) 2023 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

### Setup
DUMP=""
TMP_DIR=$(mktemp -d)
EXTRACT_KERNEL=true
declare -a MODULE_FOLDERS=("vendor_ramdisk" "vendor_dlkm" "system_dlkm")

curl -sSL "https://raw.githubusercontent.com/PabloCastellano/extract-dtb/master/extract_dtb/extract_dtb.py" > ${TMP_DIR}/extract_dtb.py

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-kernel )
                EXTRACT_KERNEL=false
                ;;
        * )
                DUMP="${1}"
                ;;
    esac
    shift
done

[ -f "./Module.symvers" ] || touch "./Module.symvers"
[ -f "./System.map" ] || touch "./System.map"

# Check if dump is specified and exists
if [ -z "${DUMP}" ]; then
    echo "Please specify the dump!"
    exit 1
elif [ ! -d "${DUMP}" ]; then
    echo "Unable to find dump at ${DUMP}!"
    exit 1
fi

echo "Extracting files from ${DUMP}:"

## Kernel
if ${EXTRACT_KERNEL}; then
    echo "Extracting boot image.."
    ../../../system/tools/mkbootimg/unpack_bootimg.py \
        --boot_img "${DUMP}/boot.img" \
        --out "${TMP_DIR}/boot.out" > /dev/null
    cp -f "${TMP_DIR}/boot.out/kernel" ./Image
    echo "  - Image"
fi

## ikconfig
# Cleanup
rm ./.config

echo "Copying ikconfig.."
cp -f "${DUMP}/ikconfig" ./.config
echo " - .config"

## DTBS
# Cleanup / Preparation
rm -rf "./dtbs"
mkdir "./dtbs"

echo "Extracting vendor_boot image..."
../../../system/tools/mkbootimg/unpack_bootimg.py \
    --boot_img "${DUMP}/vendor_boot.img" \
    --out "${TMP_DIR}/vendor_boot.out" > /dev/null

# Copy
python3 "${TMP_DIR}/extract_dtb.py" "${TMP_DIR}/vendor_boot.out/dtb" -o "${TMP_DIR}/dtbs" > /dev/null
find "${TMP_DIR}/dtbs" -type f -name "*.dtb" \
    -exec cp {} "./dtbs" \; \
    -exec printf "  - dtbs/" \; \
    -exec basename {} \;

cp -f "${DUMP}/dtbo.img" "./dtbo.img"
echo "  - ./dtbo.img"

## Modules
# Cleanup / Preparation
for MODULE_FOLDER in "${MODULE_FOLDERS[@]}"; do
    rm -rf "./${MODULE_FOLDER}"
    mkdir "./${MODULE_FOLDER}"
done

# Copy
for MODULE_FOLDER in "${MODULE_FOLDERS[@]}"; do
    MODULE_SRC="${DUMP}/${MODULE_FOLDER}"
    if [ "${MODULE_FOLDER}" == "vendor_ramdisk" ]; then
        lz4 -qd "${TMP_DIR}/vendor_boot.out/vendor_ramdisk00" "${TMP_DIR}/vendor_ramdisk.cpio"
        7z x "${TMP_DIR}/vendor_ramdisk.cpio" -o"${TMP_DIR}/vendor_ramdisk" > /dev/null
        MODULE_SRC="${TMP_DIR}/vendor_ramdisk"
    fi
    [ -d "${MODULE_SRC}" ] || break
    find "${MODULE_SRC}/lib/modules" -type f \
        -exec cp {} "./${MODULE_FOLDER}/" \; \
        -exec printf "  - ${MODULE_FOLDER}/" \; \
        -exec basename {} \;
done

# Clear temp dir
rm -rf "${TMP_DIR}"