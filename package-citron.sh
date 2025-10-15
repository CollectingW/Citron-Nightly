#!/bin/sh
set -ex
ARCH="${ARCH:-$(uname -m)}"

# The VERSION is now passed as an environment variable from the workflow
if [ -z "$APP_VERSION" ]; then
    echo "Error: APP_VERSION environment variable is not set."
    exit 1
fi

# Construct unique names for the AppImage and tarball based on the build matrix.
OUTNAME_BASE="citron_nightly-${APP_VERSION}-linux-${ARCH}${ARCH_SUFFIX}"
export OUTNAME_APPIMAGE="${OUTNAME_BASE}.AppImage"
export OUTNAME_TAR="${OUTNAME_BASE}.tar.zst"

URUNTIME="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/uruntime2appimage.sh"
SHARUN="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh"

export DESKTOP=/usr/share/applications/org.citron_emu.citron.desktop
export ICON=/usr/share/icons/hicolor/scalable/apps/org.citron_emu.citron.svg
export DEPLOY_OPENGL=1
export DEPLOY_VULKAN=1
export DEPLOY_PIPEWIRE=1

wget --retry-connrefused --tries=30 "$SHARUN" -O ./quick-sharun
chmod +x ./quick-sharun

./quick-sharun /usr/bin/citron* /usr/lib/libgamemode.so* /usr/lib/libpulse.so*

echo "Copying Qt translation files..."

mkdir -p ./AppDir/usr/share/qt6

cp -r /usr/share/qt6/translations ./AppDir/usr/share/qt6/

if [ "$DEVEL" = 'true' ]; then
	sed -i 's|Name=citron|Name=citron nightly|' ./AppDir/*.desktop
fi

echo 'SHARUN_ALLOW_SYS_VK_ICD=1' > ./AppDir/.env


echo "Creating tar.zst archive..."

(cd AppDir && tar -c --zstd -f ../"$OUTNAME_TAR" usr)
echo "Successfully created $OUTNAME_TAR"


wget --retry-connrefused --tries=30 "$URUNTIME" -O ./uruntime2appimage
chmod +x ./uruntime2appimage

./uruntime2appimage

echo "Renaming versioned AppImage to the final suffixed name: ${OUTNAME_APPIMAGE}..."

SOURCE_APPIMAGE="citron_nightly-${APP_VERSION}-${ARCH}.AppImage"

mv -v "${SOURCE_APPIMAGE}" "${OUTNAME_APPIMAGE}"
mv -v "${SOURCE_APPIMAGE}.zsync" "${OUTNAME_APPIMAGE}.zsync"

mkdir -p ./dist

mv -v ./*.AppImage* ./dist
mv -v ./*.tar.zst ./dist
