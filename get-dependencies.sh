#!/bin/sh

set -ex
ARCH="$(uname -m)"

pacman -Syu --noconfirm --needed \
	base-devel          \
	boost               \
	boost-libs          \
	catch2              \
	clang               \
	cmake               \
	curl                \
	enet                \
	fmt                 \
	ffmpeg              \
	gamemode            \
	gcc                 \
	git                 \
	glslang             \
	glu                 \
	hidapi              \
	libdecor            \
	libvpx              \
	libxi               \
	libxkbcommon-x11    \
	libxss              \
	lld                 \
	llvm                \
	mbedtls2            \
	mesa                \
	nasm                \
	ninja               \
	nlohmann-json       \
	numactl             \
	openal              \
	pulseaudio          \
	pulseaudio-alsa     \
	qt6-base            \
	qt6-networkauth     \
	qt6-multimedia      \
	qt6-tools           \
	qt6-wayland         \
	qt6-translations    \
	sdl2                \
	unzip               \
	vulkan-headers      \
	vulkan-mesa-layers  \
	wget                \
	xcb-util-cursor     \
	xcb-util-image      \
	xcb-util-renderutil \
	xcb-util-wm         \
	xorg-server-xvfb    \
	zip                 \
	zsync
