#!/bin/bash -e

function readlink() {
  DIR=$(echo "${1%/*}")
  (cd "$DIR" && echo "$(pwd -P)")
}

function build_android() {
    case "$(uname -s)" in
        Darwin)
            ANDROID_NDK_HOME=~/Library/Android/sdk/ndk-bundle

            ;;
        *)
            ;;
    esac

    NDK_PLATFORM=${NDK_PLATFORM:-"android-16"}
    NDK_PLATFORM_COMPAT="${NDK_PLATFORM_COMPAT:-${NDK_PLATFORM}}"
    NDK_API_VERSION=$(echo "$NDK_PLATFORM" | sed 's/^android-//')
    NDK_API_VERSION_COMPAT=$(echo "$NDK_PLATFORM_COMPAT" | sed 's/^android-//')

    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "You should set ANDROID_NDK_HOME to the directory containing the Android NDK"
        exit 1
    fi

    INSTALL_PREFIX="$PREFIX/android/${TARGET_ARCH}"
    MAKE_TOOLCHAIN="${ANDROID_NDK_HOME}/build/tools/make_standalone_toolchain.py"
    TOOLCHAIN_DIR="$(pwd)/android-toolchain-${TARGET_ARCH}"

    OLD_PATH=${PATH}
    export PATH="${PATH}:${TOOLCHAIN_DIR}/bin"
    export CC="${HOST_COMPILER}-clang"

    rm -rf "${TOOLCHAIN_DIR}" "${INSTALL_PREFIX}"
    make distclean > /dev/null || true

    "$MAKE_TOOLCHAIN" --force --api="$NDK_API_VERSION_COMPAT" --arch="$ARCH" --install-dir="$TOOLCHAIN_DIR" || exit 1

    ./configure \
        --host="${HOST_COMPILER}" \
        --with-pic \
        --enable-static \
        --disable-shared \
        --disable-nls \
        --disable-languages \
        --disable-tests \
        --with-sysroot="${TOOLCHAIN_DIR}/sysroot" \
        --prefix="${INSTALL_PREFIX}"

    make -j${PROCESSORS} install

    export PATH=${OLD_PATH}
}

NPROCESSORS=$(getconf NPROCESSORS_ONLN 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null)
PROCESSORS=${NPROCESSORS:-3}

LIBGPG_ERROR_VERSION=1.28
LIBGPG_ERROR_PACKAGE="libgpg-error-${LIBGPG_ERROR_VERSION}"

PREFIX="$(pwd)/../../build/libgpg-error/"
mkdir -p ${PREFIX}
PREFIX=$(readlink "${PREFIX}")

cd ${LIBGPG_ERROR_PACKAGE}

case ${PLATFORM} in
    IOS)
        IOS64_PREFIX="$PREFIX/ios/arm64"
        SIMULATOR64_PREFIX="$PREFIX/ios/simulator64"

        mkdir -p ${IOS64_PREFIX} ${SIMULATOR64_PREFIX}

        XCODEDIR=$(xcode-select -p)
        IOS_SIMULATOR_VERSION_MIN=${IOS_SIMULATOR_VERSION_MIN-"6.0.0"}
        IOS_VERSION_MIN=${IOS_VERSION_MIN-"6.0.0"}

        # Build for the simulator
        BASEDIR="${XCODEDIR}/Platforms/iPhoneSimulator.platform/Developer"
        PATH="${BASEDIR}/usr/bin:$BASEDIR/usr/sbin:$PATH"
        SDK="${BASEDIR}/SDKs/iPhoneSimulator.sdk"

        # x86_64 simulator
        export CFLAGS="-O2 -arch x86_64 -isysroot ${SDK} -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"
        export LDFLAGS="-arch x86_64 -isysroot ${SDK} -mios-simulator-version-min=${IOS_SIMULATOR_VERSION_MIN}"

        make distclean > /dev/null || true

        ./configure \
            --host=x86_64-apple-darwin \
            --with-pic \
            --enable-static \
            --disable-shared \
            --disable-nls \
            --disable-languages \
            --disable-tests \
            --prefix="${SIMULATOR64_PREFIX}"

        make -j${PROCESSORS} install

        # Build for iOS
        BASEDIR="${XCODEDIR}/Platforms/iPhoneOS.platform/Developer"
        PATH="${BASEDIR}/usr/bin:$BASEDIR/usr/sbin:$PATH"
        SDK="${BASEDIR}/SDKs/iPhoneOS.sdk"

        ## 64-bit iOS
        export CFLAGS="-fembed-bitcode -O2 -arch arm64 -isysroot ${SDK} -mios-version-min=${IOS_VERSION_MIN} -fembed-bitcode"
        export LDFLAGS="-fembed-bitcode -arch arm64 -isysroot ${SDK} -mios-version-min=${IOS_VERSION_MIN} -fembed-bitcode"

        make distclean > /dev/null

        ./configure \
            --host=arm-apple-darwin \
            --with-pic \
            --enable-static \
            --disable-shared \
            --disable-nls \
            --disable-languages \
            --disable-tests \
            --prefix="${IOS64_PREFIX}"

        make -j${PROCESSORS} install

        # Create universal binary and include folder
        rm -fr -- "${PREFIX}/include" "${PREFIX}/lib/libgpg-error.a" 2> /dev/null
        mkdir -p -- "${PREFIX}/lib"
        lipo -create \
            "${SIMULATOR64_PREFIX}/lib/libgpg-error.a" \
            "${IOS64_PREFIX}/lib/libgpg-error.a" \
            -output "${PREFIX}/lib/libgpg-error.a"
        cp -rf -- "${SIMULATOR64_PREFIX}/include" "$PREFIX/"

        # Cleanup
        make distclean > /dev/null

        ;;
    ANDROID)
        # Fix compilation errors by:
        #   1. Patching src/logging.c to avoid passing NULL as va_list.
        #   2. Manually generating:
        #      - syscfg/lock-obj-pub.x86_64-pc-linux-android.h
        #      - syscfg/lock-obj-pub.aarch64-unknown-linux-androideabi.h

        patch -p0 -N < ../libgpg-error.patch || true

        # These configuration files match exactly what gets generated by gen-posix-lock-obj on arm64 and x86_64.
	    cp -f src/syscfg/lock-obj-pub.x86_64-pc-linux-gnu.h src/syscfg/lock-obj-pub.aarch64-unknown-linux-androideabi.h
        cp -f src/syscfg/lock-obj-pub.arm-unknown-linux-androideabi.h src/syscfg/lock-obj-pub.linux-android.h

        # Build for armv7a
        TARGET_ARCH="armv7-a"
        CFLAGS="-Os -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb -marm -march=${TARGET_ARCH}"
        ARCH="arm"
        HOST_COMPILER="arm-linux-androideabi"
        build_android

        # Build for armv8-a
        TARGET_ARCH="armv8-a"
        CFLAGS="-Os -march=${TARGET_ARCH}"
        ARCH="arm64"
        HOST_COMPILER="aarch64-linux-android"
        NDK_PLATFORM="android-21"
        NDK_PLATFORM_COMPAT="android-21"
        build_android

        # Build for x86
        TARGET_ARCH="i686"
        CFLAGS="-Os -march=${TARGET_ARCH}"
        ARCH="x86"
        HOST_COMPILER="i686-linux-android"
        NDK_PLATFORM="android-21"
        NDK_PLATFORM_COMPAT="android-21"
        build_android

        # Build for x86_64
        TARGET_ARCH="westmere"
        CFLAGS="-Os -march=${TARGET_ARCH}"
        ARCH="x86_64"
        HOST_COMPILER="x86_64-linux-android"
        NDK_PLATFORM="android-21"
        NDK_PLATFORM_COMPAT="android-21"
        build_android

        ;;
    *)
        make distclean > /dev/null || true

        ./configure \
            --with-pic \
            --enable-static \
            --disable-shared \
            --disable-nls \
            --disable-languages \
            --prefix="${PREFIX}"

        make -j${PROCESSORS} install

        if [ -n "${CI}" ] ; then
            make -j${PROCESSORS} check
        fi

        make distclean > /dev/null || true

        ;;
esac
