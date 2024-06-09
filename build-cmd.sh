#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

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
 
VERSION_HEADER_FILE="$ZLIB_SOURCE_DIR/zlib.h.in"
version=$(sed -n -E 's/#define ZLIBNG_VERSION "([0-9.]+)"/\1/p' "${VERSION_HEADER_FILE}")
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

# create stading dir structures
mkdir -p "$stage/include/zlib"
mkdir -p "$stage/lib/debug"
mkdir -p "$stage/lib/release"

pushd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            mkdir -p "build"
            pushd "build"
                # Invoke cmake and use as official build
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DBUILD_SHARED_LIBS=OFF -DZLIB_COMPAT:BOOL=ON

                cmake --build . --config Debug
                cmake --build . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                    ctest -C Release
                fi

                cp -a "Debug/zlibstaticd.lib" "$stage/lib/debug/zlibd.lib"
                cp -a "Release/zlibstatic.lib" "$stage/lib/release/zlib.lib"
                cp -a zconf.h "$stage/include/zlib"
                cp -a zlib.h "$stage/include/zlib"
                cp -a "zlib_name_mangling.h" "$stage/include/zlib"
            popd
        ;;

        # ------------------------- darwin, darwin64 -------------------------
        darwin*)
            # Setup build flags
            C_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
            C_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"

            # deploy target
            export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

            mkdir -p "build_x86"
            pushd "build_x86"
                cmake .. -G Ninja -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_C_FLAGS="$C_OPTS_X86" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_ARCHITECTURES="x86_64" \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            mkdir -p "build_arm64"
            pushd "build_arm64"
                cmake .. -G Ninja -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/release_arm64"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # create fat libraries
            lipo -create ${stage}/release_x86/lib/libz.a ${stage}/release_arm64/lib/libz.a -output ${stage}/lib/release/libz.a

            # headers are the same between x86_64 and arm64
            mv $stage/release_x86/include/* $stage/include/zlib
        ;;            

        # -------------------------- linux, linux64 --------------------------
        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CFLAGS}"

            mkdir -p "build"
            pushd "build"
                CFLAGS="$opts" \
                CPPFLAGS="$LL_BUILD_RELEASE_MACROS" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage/release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/release/lib/*.a ${stage}/lib/

            # copy headers
            mv $stage/release/include/* $stage/include/zlib
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    # The copyright info for zlib is the tail end of its README file. Tempting
    # though it is to write something like 'tail -n 31 README', that will
    # quietly fail if the length of the copyright notice ever changes.
    # Instead, look for the section header that sets off that passage and copy
    # from there through EOF. (Given that END is recognized by awk, you might
    # reasonably expect '/pattern/,END' to work, but no: END can only be used
    # to fire an action past EOF. Have to simulate by using another regexp we
    # hope will NOT match.)
    cp LICENSE.md "$stage/LICENSES/zlib-ng.txt"
    # In case the section header changes, ensure that zlib.txt is non-empty.
    # (With -e in effect, a raw test command has the force of an assert.)
    # Exiting here means we failed to match the copyright section header.
    # Check the README and adjust the awk regexp accordingly.
    [ -s "$stage/LICENSES/zlib-ng.txt" ]
popd
