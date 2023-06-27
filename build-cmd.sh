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
echo "${version}" > "${stage}/VERSION.txt"

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
            popd
        ;;

        # ------------------------- darwin, darwin64 -------------------------
        darwin*)
            # Setup osx sdk platform
            SDKNAME="macosx"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)

            # Setup build flags
            ARCH_FLAGS_X86="-arch x86_64 -mmacosx-version-min=10.15 -isysroot ${SDKROOT} -msse4.2"
            ARCH_FLAGS_ARM64="-arch arm64 -mmacosx-version-min=11.0 -isysroot ${SDKROOT}"
            DEBUG_COMMON_FLAGS="-O0 -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="-O3 -g -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="-Wl,-headerpad_max_install_names"
            RELEASE_LDFLAGS="-Wl,-headerpad_max_install_names"

            # x86 deploy target
            export MACOSX_DEPLOYMENT_TARGET=10.15

            mkdir -p "build_debug_x86"
            pushd "build_debug_x86"
                CFLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_X86 $DEBUG_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 $DEBUG_LDFLAGS" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON -DWITH_OPTIM:BOOL=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_OSX_ARCHITECTURES="x86_64" \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/debug_x86"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_X86 $RELEASE_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_X86 ${RELEASE_LDFLAGS}" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="3" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
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

            # ARM64 Deploy Target
            export MACOSX_DEPLOYMENT_TARGET=11.0

            mkdir -p "build_debug_arm64"
            pushd "build_debug_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_LDFLAGS" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON -DWITH_OPTIM:BOOL=OFF \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/debug_arm64"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                CXXFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                CPPFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CPPFLAGS" \
                LDFLAGS="$ARCH_FLAGS_ARM64 ${RELEASE_LDFLAGS}" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="3" \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf \
                    -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                    -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                    -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
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
            lipo -create ${stage}/debug_x86/lib/libz.a ${stage}/debug_arm64/lib/libz.a -output ${stage}/lib/debug/libz.a
            lipo -create ${stage}/release_x86/lib/libz.a ${stage}/release_arm64/lib/libz.a -output ${stage}/lib/release/libz.a

            # headers are the same between x86_64 and arm64
            mv $stage/release_x86/include/* $stage/include/zlib
        ;;            

        # -------------------------- linux, linux64 --------------------------
        linux*)
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"

            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_BUILD_TYPE="Debug" \
                    -DCMAKE_C_FLAGS="$DEBUG_CFLAGS" \
                    -DCMAKE_INSTALL_PREFIX="$stage/debug"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DZLIB_COMPAT:BOOL=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                    -DCMAKE_INSTALL_PREFIX="$stage/release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/debug/lib/*.a ${stage}/lib/debug/
            cp -a ${stage}/release/lib/*.a ${stage}/lib/release/

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
