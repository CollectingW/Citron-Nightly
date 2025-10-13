#!/bin/sh
set -ex

ARCH="${ARCH:-$(uname -m)}"
BUILD_PGO=false

if [ "$1" = 'v3-pgo' ] && [ "$ARCH" = 'x86_64' ]; then
    ARCH_FLAGS="-march=x86-64-v3 -O3 -USuccess -UNone -fuse-ld=lld"
    BUILD_PGO=true
elif [ "$1" = 'pgo' ] && [ "$ARCH" = 'x86_64' ]; then
    ARCH_FLAGS="-march=x86-64 -mtune=generic -O3 -USuccess -UNone -fuse-ld=lld"
    BUILD_PGO=true
elif [ "$1" = 'v3' ] && [ "$ARCH" = 'x86_64' ]; then
	ARCH_FLAGS="-march=x86-64-v3 -O3 -USuccess -UNone -fuse-ld=lld"
elif [ "$ARCH" = 'x86_64' ]; then
	ARCH_FLAGS="-march=x86-64 -mtune=generic -O3 -USuccess -UNone -fuse-ld=lld"
else

	ARCH_FLAGS="-march=armv8-a -mtune=generic -O3 -USuccess -UNone -fuse-ld=lld"

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

find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::asio::io_service\b/boost::asio::io_context/g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::asio::io_service::strand\b/boost::asio::strand<boost::asio::io_context::executor_type>/g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's|#include *<boost/process/async_pipe.hpp>|#include <boost/process/v1/async_pipe.hpp>|g'
find . -type f \( -name '*.cpp' -o -name '*.h' \) | xargs sed -i 's/\bboost::process::async_pipe\b/boost::process::v1::async_pipe/g'
sed -i '/sse2neon/d' ./src/video_core/CMakeLists.txt
sed -i '/sse2neon/d' ./src/video_core/CMakeLists.txt
sed -i 's/cmake_minimum_required(VERSION 2.8)/cmake_minimum_required(VERSION 3.5)/' externals/xbyak/CMakeLists.txt

HEADER_PATH=$(pacman -Ql qt6-base | grep 'qpa/qplatformnativeinterface.h$' | awk '{print $2}')
if [ -z "$HEADER_PATH" ]; then
    echo "ERROR: Could not find qplatformnativeinterface.h path." >&2
    exit 1
fi
QT_PRIVATE_INCLUDE_DIR=$(dirname "$(dirname "$HEADER_PATH")")
CXX_FLAGS_EXTRA="-I${QT_PRIVATE_INCLUDE_DIR}"

if [ -z "$JOBS" ]; then JOBS=$(nproc --all); fi

if [ "$BUILD_PGO" = true ]; then
    # STAGE 1: Build with instrumentation using manual flags for reliability
    mkdir build_instrumented && cd build_instrumented
    PGO_FLAGS="-fprofile-generate"
    cmake .. -GNinja \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCITRON_USE_BUNDLED_VCPKG=OFF -DCITRON_USE_BUNDLED_QT=OFF -DUSE_SYSTEM_QT=ON -DENABLE_QT6=ON \
        -DCITRON_USE_BUNDLED_FFMPEG=OFF -DCITRON_USE_BUNDLED_SDL2=ON -DCITRON_USE_EXTERNAL_SDL2=OFF \
        -DCITRON_TESTS=OFF -DCITRON_CHECK_SUBMODULES=OFF -DCITRON_USE_LLVM_DEMANGLE=OFF \
        -DCITRON_ENABLE_LTO=ON -DCITRON_USE_QT_MULTIMEDIA=ON -DCITRON_USE_QT_WEB_ENGINE=OFF \
        -DENABLE_QT_TRANSLATION=ON -DUSE_DISCORD_PRESENCE=ON -DBUNDLE_SPEEX=ON -DCITRON_USE_FASTER_LD=OFF \
        -DCITRON_USE_EXTERNAL_Vulkan_HEADERS=ON -DCITRON_USE_EXTERNAL_VULKAN_UTILITY_LIBRARIES=ON \
        -DCITRON_ENABLE_UPDATER=OFF -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_CXX_FLAGS="$ARCH_FLAGS $PGO_FLAGS -Wno-error -w ${CXX_FLAGS_EXTRA}" \
        -DCMAKE_C_FLAGS="$ARCH_FLAGS $PGO_FLAGS" \
        -DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    ninja -j${JOBS}

    # STAGE 2: Generate, merge, and copy profile data
    echo "Starting instrumented application to generate profile data..."
    export LLVM_PROFILE_FILE="${PWD}/citron.profraw"
    xvfb-run -a --server-args="-screen 0 1024x768x24" ./bin/citron &
    XVFB_PID=$!
    echo "Running for 20 seconds to collect data... (PID: $XVFB_PID)"
    sleep 20
    echo "Stopping application..."
    kill -9 $XVFB_PID || true
    echo "Application stopped."
    llvm-profdata merge -o ./default.profdata "${LLVM_PROFILE_FILE}"
    
    cd .. && rm -rf build && mkdir build
    echo "Copying profile data to the final build directory..."
    cp build_instrumented/default.profdata build/
    cd build

    # STAGE 3: Build again using manual flags for reliability
    PGO_FLAGS="-fprofile-use=${PWD}/default.profdata"
    cmake .. -GNinja \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCITRON_USE_BUNDLED_VCPKG=OFF -DCITRON_USE_BUNDLED_QT=OFF -DUSE_SYSTEM_QT=ON -DENABLE_QT6=ON \
        -DCITRON_USE_BUNDLED_FFMPEG=OFF -DCITRON_USE_BUNDLED_SDL2=ON -DCITRON_USE_EXTERNAL_SDL2=OFF \
        -DCITRON_TESTS=OFF -DCITRON_CHECK_SUBMODULES=OFF -DCITRON_USE_LLVM_DEMANGLE=OFF \
        -DCITRON_ENABLE_LTO=ON -DCITRON_USE_QT_MULTIMEDIA=ON -DCITRON_USE_QT_WEB_ENGINE=OFF \
        -DENABLE_QT_TRANSLATION=ON -DUSE_DISCORD_PRESENCE=ON -DBUNDLE_SPEEX=ON -DCITRON_USE_FASTER_LD=OFF \
        -DCITRON_USE_EXTERNAL_Vulkan_HEADERS=ON -DCITRON_USE_EXTERNAL_VULKAN_UTILITY_LIBRARIES=ON \
        -DCITRON_ENABLE_UPDATER=OFF -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_CXX_FLAGS="$ARCH_FLAGS $PGO_FLAGS -Wno-error -w ${CXX_FLAGS_EXTRA}" \
        -DCMAKE_C_FLAGS="$ARCH_FLAGS $PGO_FLAGS" \
        -DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
else
    # REGULAR BUILD
    mkdir build && cd build
    cmake .. -GNinja \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCITRON_USE_BUNDLED_VCPKG=OFF -DCITRON_USE_BUNDLED_QT=OFF -DUSE_SYSTEM_QT=ON -DENABLE_QT6=ON \
        -DCITRON_USE_BUNDLED_FFMPEG=OFF -DCITRON_USE_BUNDLED_SDL2=ON -DCITRON_USE_EXTERNAL_SDL2=OFF \
        -DCITRON_TESTS=OFF -DCITRON_CHECK_SUBMODULES=OFF -DCITRON_USE_LLVM_DEMANGLE=OFF \
        -DCITRON_ENABLE_LTO=ON -DCITRON_USE_QT_MULTIMEDIA=ON -DCITRON_USE_QT_WEB_ENGINE=OFF \
        -DENABLE_QT_TRANSLATION=ON -DUSE_DISCORD_PRESENCE=ON -DBUNDLE_SPEEX=ON -DCITRON_USE_FASTER_LD=OFF \
        -DCITRON_USE_EXTERNAL_Vulkan_HEADERS=ON -DCITRON_USE_EXTERNAL_VULKAN_UTILITY_LIBRARIES=ON \
        -DCITRON_ENABLE_UPDATER=OFF -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_CXX_FLAGS="$ARCH_FLAGS -Wno-error -w ${CXX_FLAGS_EXTRA}" \
        -DCMAKE_C_FLAGS="$ARCH_FLAGS" \
        -DCMAKE_SYSTEM_PROCESSOR="$(uname -m)" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
fi

ninja -j${JOBS}
sudo ninja install
echo "$VERSION" >~/version
