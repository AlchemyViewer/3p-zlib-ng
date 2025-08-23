#!/usr/bin/env bash

cd "$(dirname "$0")"

set -eux

ZLIB_SOURCE_DIR="zlib-ng"

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
    windows*)
        autobuild="$(cygpath -u "$AUTOBUILD")"
    ;;
    *)
        autobuild="$AUTOBUILD"
    ;;
esac
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd apply_patch
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

apply_patch "$top/patches/fix-macos-arm64-and-win-build.patch" "$ZLIB_SOURCE_DIR"

VERSION_HEADER_FILE="$ZLIB_SOURCE_DIR/zlib.h.in"
version=$(sed -n -E 's/#define ZLIBNG_VERSION "([0-9.]+)"/\1/p' "${VERSION_HEADER_FILE}")
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

pushd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            for arch in sse avx2 arm64 ; do
                platform_target="x64"
                if [[ "$arch" == "avx2" ]]; then
                    opts="$(replace_switch /arch:SSE4.2 /arch:AVX2 $opts)"
                elif [[ "$arch" == "avx2" ]]; then
                    platform_target="ARM64"
                fi

                mkdir -p "build_debug_$arch"
                pushd "build_debug_$arch"
                    opts="$(replace_switch /Zi /Z7 $LL_BUILD_DEBUG)"
                    plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                    cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DBUILD_SHARED_LIBS=OFF -DZLIB_COMPAT:BOOL=ON \
                            -DCMAKE_GENERATOR_PLATFORM="$platform_target" \
                            -DCMAKE_CONFIGURATION_TYPES="Debug" \
                            -DCMAKE_C_FLAGS_DEBUG="$plainopts" \
                            -DCMAKE_CXX_FLAGS_DEBUG="$opts /EHsc" \
                            -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="Embedded" \
                            -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)" \
                            -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/$arch/debug")" \
                            -DCMAKE_INSTALL_INCLUDEDIR="$(cygpath -m "$stage/include/zlib-ng")"

                    cmake --build . --config Debug --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Debug

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Debug --parallel $AUTOBUILD_CPU_COUNT
                    fi

                    mv "$stage/lib/$arch/debug/zlibstaticd.lib" "$stage/lib/$arch/debug/zlibd.lib"
                popd

                mkdir -p "build_release_$arch"
                pushd "build_release_$arch"
                    opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
                    plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                    cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DBUILD_SHARED_LIBS=OFF -DZLIB_COMPAT:BOOL=ON \
                            -DCMAKE_CONFIGURATION_TYPES="Release" \
                            -DCMAKE_C_FLAGS="$plainopts" \
                            -DCMAKE_CXX_FLAGS="$opts /EHsc" \
                            -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="Embedded" \
                            -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)" \
                            -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/$arch/release")" \
                            -DCMAKE_INSTALL_INCLUDEDIR="$(cygpath -m "$stage/include/zlib-ng")"

                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                    fi

                    mv "$stage/lib/$arch/release/zlibstatic.lib" "$stage/lib/$arch/release/zlib.lib"
                popd
            done
        ;;

        # ------------------------- darwin, darwin64 -------------------------
        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                cc_opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $cc_opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -G "Xcode" -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                        -DCMAKE_CONFIGURATION_TYPES="Release" \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$cc_opts" \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_INSTALL_INCLUDEDIR="$stage/include/zlib-ng" \
                        -DCMAKE_OSX_ARCHITECTURES="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}

                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                    fi
                popd
            done

            lipo -create -output "$stage/lib/release/libz.a" "$stage/lib/release/x86_64/libz.a" "$stage/lib/release/arm64/libz.a"
        ;;

        # -------------------------- linux, linux64 --------------------------
        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Release
            mkdir -p "build"
            pushd "build"
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$(remove_cxxstd $opts)" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_INSTALL_LIBDIR="$stage/lib/release" \
                    -DCMAKE_INSTALL_INCLUDEDIR="$stage/include/zlib-ng"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                fi
            popd
        ;;
    esac

    mkdir -p "$stage/LICENSES"
    cp LICENSE.md "$stage/LICENSES/zlib-ng.txt"
popd

mkdir -p "$stage"/docs/zlib-ng/
