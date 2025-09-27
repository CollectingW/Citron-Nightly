#!/bin/sh
set -ex
ARCH="${ARCH:-$(uname -m)}"
if [ "$1" = 'v3' ] && [ "$ARCH" = 'x86_64' ]; then
	ARCH_FLAGS="-march=x86-64-v3 -O3 -USuccess -UNone"
elif [ "$ARCH" = 'x86_64' ]; then
	ARCH_FLAGS="-march=x86-64 -mtune=generic -O3 -USuccess -UNone"
else
	ARCH_FLAGS="-march=armv8-a -mtune=generic -O3 -USuccess -UNone"
fi
git clone --recursive "https://git.citron-emu.org/citron/emulator.git" ./citron
cd ./citron
if [ "$DEVEL" = 'true' ]; then
	CITRON_TAG="$(git rev-parse --short HEAD)"
	VERSION="$CITRON_TAG"
else
	CITRON_TAG=$(git describe --tags)
	git checkout "$CITRON_TAG"
	VERSION="$(echo "$CITRON_TAG" | awk -F'-' '{print $1}')"
fi
# Apply compatibility patches for newer Boost versions found in the Arch container
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::asio::io_service\b/boost::asio::io_context/g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::asio::io_service::strand\b/boost::asio::strand<boost::asio::io_context::executor_type>/g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's|#include *<boost/process/async_pipe.hpp>|#include <boost/process/v1/async_pipe.hpp>|g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::process::async_pipe\b/boost::process::v1::async_pipe/g'
sed -i '/sse2neon/d' ./src/video_core/CMakeLists.txt
sed -i '/sse2neon/d' ./src/video_core/CMakeLists.txt
mkdir build
cd build
cmake .. -GNinja \
	-DCITRON_USE_BUNDLED_VCPKG=OFF -DCITRON_USE_BUNDLED_QT=OFF -DUSE_SYSTEM_QT=ON -DENABLE_QT6=ON \
	-DCITRON_USE_BUNDLED_FFMPEG=OFF -DCITRON_USE_BUNDLED_SDL2=ON -DCITRON_USE_EXTERNAL_SDL2=OFF \
	-DCITRON_TESTS=OFF -DCITRON_CHECK_SUBMODULES=OFF -DCITRON_USE_LLVM_DEMANGLE=OFF \
	-DCITRON_ENABLE_LTO=ON -DCITRON_USE_QT_MULTIMEDIA=ON -DCITRON_USE_QT_WEB_ENGINE=OFF \
	-DENABLE_QT_TRANSLATION=ON -DUSE_DISCORD_PRESENCE=OFF -DBUNDLE_SPEEX=ON -DCITRON_USE_FASTER_LD=OFF \
	-DCITRON_USE_EXTERNAL_VULKAN_HEADERS=ON -DCITRON_USE_EXTERNAL_VULKAN_UTILITY_LIBRARIES=ON \
	-DCITRON_ENABLE_UPDATER=OFF -DCMAKE_INSTALL_PREFIX=/usr \
	-DCMAKE_CXX_FLAGS="$ARCH_FLAGS -Wno-error -w" -DCMAKE_C_FLAGS="$ARCH_FLAGS" \
	-DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
if [ -z "$JOBS" ]; then JOBS=$(nproc --all); fi
ninja -j${JOBS}
sudo ninja install
echo "$VERSION" >~/version
