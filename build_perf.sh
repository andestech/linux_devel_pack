#!/usr/bin/env bash

# === Must use bash to run this script ===
execute_env=`ps -p $$`
which_bash=`which bash`
if [ "${execute_env##* }" != 'bash' ]; then
    echo "!! Error: Please use \"$which_bash\" to run or execute with ./Prepare_rootfs.sh , not \"${execute_env##* }\""
    exit
fi

# === argurment parsing ===
for var in $@; do
    case "$var" in
        --toolchain_path=*)
            TOOLCHAIN_PATH=${var#*=}
            ;;
        --linux_path=*)
            LINUX_PATH=${var#*=}
            ;;
        --ramdisk_root_path=*)
            RAMDISK_PATH=${var#*=}
            ;;
        --cross_compile=*)
            CROSS_COMPILE=${var#*=}
            ;;
        --arch=*)
            ARCH=${var#*=}
            ;;
        --help)
             echo ""
             echo "[[ help message ]]"
             echo "==== required argument ===="
             echo "--toolchain_path= Specify a toolchain directory (EX: \$PWD/nds32le-linux-glibc-v5d)"
             echo "--linux_path= Specify the absolute path to the linux kernel folder"
             echo "--ramdisk_root_path= Specify a directory containing files for building root file system."
             echo ""
             echo "==== optional arguments ===="
             echo "--cross_compile=riscv[32|64]-linux- (Default: riscv32-linux-)"
             echo "--arch=rv[32|64]v5[d] Specify the architecture. (Default: rv32v5d)"
             exit 0
             ;;
        *)
             echo ""
             echo "!! Error: unrecognized parameter ${var} !!"
             echo ""
             ;;
    esac
done

# === set default value if user doesn't give value ===
CROSS_COMPILE=${CROSS_COMPILE:=riscv32-linux-}
ARCH=${ARCH:=rv32v5d}
ARCH_FLAG="-march=${ARCH}"
PATH=${TOOLCHAIN_PATH}/bin:$PATH

export CROSS_COMPILE PATH

# === sanity check ===
if [ "${TOOLCHAIN_PATH}" = "" ]; then
    echo ""
    echo "!! Error: The toolchain path is not specified. !!"
    echo "!! Error: Please specify a toolchain path. (EX: \$PWD/nds32le-linux-glibc-v5d)  !!"
    echo ""
    exit
fi

which ${CROSS_COMPILE}gcc &> /dev/null
if [ "$?" -ne ""0 ]; then
    echo ""
    echo "!! Error: Can not find $TOOLCHAIN_PATH/bin/${CROSS_COMPILE}gcc"
    echo "!! Error: Please specify a toolchain or right CROSS_COMPILE option."
    echo ""
    echo ""
    exit
fi

if [ "${ARCH}" != "rv32v5" ] && [ "${ARCH}" != "rv32v5d" ] && [ "${ARCH}" != "rv64v5" ] && [ "${ARCH}" != "rv64v5d" ]; then
    echo ""
    echo "!! Error: please check if the specified arch is rv[32|64]v5[d]."
    echo ""
    exit
fi

# Fetch the source of necessary libraries, and prepare a temporary sysroot
preprocess()
{
    mkdir -p build_perf
    cd build_perf
    export TOP=${PWD}
    cp -a ${LINUX_PATH}/tools/ ${TOP}
    mkdir -p sysroot_tmp
    mkdir -p scripts
    cp -arf ${LINUX_PATH}/scripts/bpf_doc.py ./scripts/
}

build_zlib()
{
    git clone https://github.com/madler/zlib -b v1.2.11
    cd zlib

    CC=${CROSS_COMPILE}gcc CFLAGS+=${ARCH_FLAG} ./configure --prefix=${TOP}/sysroot_tmp
    make install

    cd ${TOP}
}

patch_makefile() {
    sed -ri 's/riscv(32|64)(-unknown)?-linux-//' $1
    sed -ri 's/-Wnull-dereference//' $1
    sed -ri 's/-march=rv(32|64)v5d?//' $1
    sed -ri 's/-Wimplicit-fallthrough=5//' $1
    sed -ri 's/-Wduplicated-cond//' $1
}

build_elfutils()
{
    git clone https://sourceware.org/git/elfutils.git -b elfutils-0.178
    cd elfutils

    sed -ri 's/args\[6\]/*args/' libebl/libebl.h
    sed -ri 's/ops_mem\[3\]/*ops_mem/' libdw/libdw.h

    # Replace the deprecated macros
    sed -ri 's/AM_PROG_LEX/AC_PROG_LEX([noyywrap])/' configure.ac
    sed -ri 's/AC_HELP_STRING/AS_HELP_STRING/' configure.ac
    sed -ri 's/AC_HELP_STRING/AS_HELP_STRING/' m4/zip.m4
    sed -ri 's/AC_HELP_STRING/AS_HELP_STRING/' m4/biarch.m4

    aclocal --force -I m4
    autoconf --force
    autoheader --force
    automake --add-missing --copy --force-missing

    if [[ ${CROSS_COMPILE} =~ "64" ]]; then
        HOST="riscv64-unknown-linux"
    else
        HOST="riscv32-unknown-linux"
    fi

    ./configure CFLAGS="-O2 -I${TOP}/sysroot_tmp/include -fPIC ${ARCH_FLAG}" \
    LDFLAGS="-L${TOP}/sysroot_tmp/lib -lz" --host=${HOST} --target=${HOST} \
    --enable-maintainer-mode --disable-debuginfod --prefix=${TOP}/sysroot_tmp
    make

    cp -a ./lib ./lib.riscv
    cd lib
    patch_makefile ./Makefile
    make clean all
    cd ..
    cp -a ./libcpu/ ./libcpu.failed
    cd libcpu
    patch_makefile ./Makefile
    make clean i386_gendis
    cp ../libcpu.failed/Makefile .
    make
    cd ..
    make
    mv ./lib ./lib.x86
    cp -a ./lib.riscv/ ./lib
    make
    make install

    cd ${TOP}
}

build_traceevent()
{
    git clone https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git/ \
    --branch=libtraceevent-1.8.3 --single-branch
    cd libtraceevent

    # Modify the flag for soft-float ABI, or the linker will try to link
    # soft-float modules with hard-float modules.
    sed -ri "s/--shared/--shared ${ARCH_FLAG}/" scripts/utils.mk

    prefix='' DESTDIR=${TOP}/sysroot_tmp EXTRA_CFLAGS=${ARCH_FLAG} make install

    # Set the correct path to "prefix" in .pc file.
    sed -i "1 s|$|${TOP}/sysroot_tmp|" libtraceevent.pc
    cp libtraceevent.pc ${TOP}/sysroot_tmp/lib/pkgconfig/

    cd ${TOP}
}

build_tracefs()
{
    git clone https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git/ \
    --branch=libtracefs-1.8.1 --single-branch
    cd libtracefs

    # Export the environment variables to cross build
    sed -i '36i export CC AR' Makefile

    # Modify the flag for soft-float ABI, or the linker will try to link
    # soft-float modules with hard-float modules.
    sed -ri "s/--shared/--shared ${ARCH_FLAG}/" scripts/utils.mk

    PKG_CONFIG_PATH=${TOP}/sysroot_tmp/lib/pkgconfig \
    prefix='' DESTDIR=${TOP}/sysroot_tmp EXTRA_CFLAGS=${ARCH_FLAG} \
    make install

    # Set the correct path to "prefix" in .pc file.
    sed -i "1 s|$|$TOP/sysroot_tmp|" libtracefs.pc
    cp libtracefs.pc ${TOP}/sysroot_tmp/lib/pkgconfig/

    # Copy tracefs.h to the previous folder
    # cp ${TOP}/sysroot_tmp/include/tracefs/tracefs.h ${TOP}/sysroot_tmp/include/tracefs.h
    cd ${TOP}
}

build_slang()
{
    wget https://www.jedsoft.org/releases/slang/old/slang-2.3.2.tar.bz2
    tar jxvf slang-2.3.2.tar.bz2
    cd slang-2.3.2/

    sed -i "s/SLtt_Use_Ansi_Colors = 0;/SLtt_Use_Ansi_Colors = 1;/g" src/slvideo.c
    sed -i "s/SLtt_Use_Ansi_Colors = 0;/SLtt_Use_Ansi_Colors = 1;/g" src/sldisply.c

    if [[ ${CROSS_COMPILE} =~ "64" ]]; then
        HOST="riscv64-linux"
    else
        HOST="riscv32-linux"
    fi

    CFLAGS="${ARCH_FLAG} -I${TOP}/sysroot_tmp/include" \
    LDFLAGS="${ARCH_FLAG} -L${TOP}/sysroot_tmp/lib" \
    ./configure --host=${HOST} --target=${HOST} --prefix=${TOP}/sysroot_tmp \
    --without-pcre --without-png
    make install

    cd ${TOP}
}

copy_library()
{
    declare -A dict=(
        [rv32v5]=lib32/ilp32
        [rv32v5d]=lib32/ilp32d
        [rv64v5]=lib64/lp64
        [rv64v5d]=lib64/lp64d
    )

    for library in "${!dict[@]}"
    do
        if [ "$library" == "$ARCH" ]; then
            DEST=${RAMDISK_PATH}/rootfs/disk/${dict[$library]}
        fi
    done

    cp ${TOP}/sysroot_tmp/lib/libelf.so.1 ${DEST}
    cp ${TOP}/sysroot_tmp/lib/libdw.so.1 ${DEST}
    cp ${TOP}/sysroot_tmp/lib/libz.so.1 ${DEST}
    cp ${TOP}/sysroot_tmp/lib/libslang.so.2 ${DEST}

    if [[ ${DEST} =~ "64" ]]; then
        cp ${TOP}/sysroot_tmp/lib64/libtraceevent.so.1 ${DEST}
        cp ${TOP}/sysroot_tmp/lib64/libtracefs.so.1 ${DEST}
    else
        cp ${TOP}/sysroot_tmp/lib/libtraceevent.so.1 ${DEST}
        cp ${TOP}/sysroot_tmp/lib/libtracefs.so.1 ${DEST}
    fi
}


enable_features()
{
    cd tools/build/feature/

    CC_AND_FLAGS="CC=${CROSS_COMPILE}gcc \
    CFLAGS='-I${TOP}/sysroot_tmp/include \
    -I${TOP}/sysroot_tmp/include/traceevent \
    -I${TOP}/sysroot_tmp/include/tracefs \
    ${ARCH_FLAG}' \
    LDFLAGS='-L${TOP}/sysroot_tmp/lib/ \
    -L${TOP}/sysroot_tmp/lib64/ \
    -lz -lelf -ldw -ltraceevent -ltracefs -lslang' \
    "

    eval $CC_AND_FLAGS make test-libelf.bin
    eval $CC_AND_FLAGS make test-glibc.bin
    eval $CC_AND_FLAGS make test-pthread-attr-setaffinity-np.bin
    eval $CC_AND_FLAGS make test-dwarf.bin
    eval $CC_AND_FLAGS make test-dwarf_getlocations.bin
    eval $CC_AND_FLAGS make test-libdw-dwarf-unwind.bin
    eval $CC_AND_FLAGS make test-libelf-getphdrnum.bin
    eval $CC_AND_FLAGS make test-libelf-gelf_getnote.bin
    eval $CC_AND_FLAGS make test-libelf-getshdrstrndx.bin
    eval $CC_AND_FLAGS make test-libtraceevent.bin
    eval $CC_AND_FLAGS make test-libtracefs.bin
    eval $CC_AND_FLAGS make test-libslang.bin

    cd ${TOP}
}

build_perf()
{
    cd tools/perf

    # There is only one cpp file demangle-cxx.cpp. When trying to build perf
    # with soft-float ABI, demangle-cxx.o is still double-folated since we only
    # set CFLAGS. Thus, set CXXFLAGS for soft-float ABI.
    sed -i "346a CXXFLAGS += ${ARCH_FLAG}" Makefile.config

    ARCH=riscv CROSS_COMPILE=${CROSS_COMPILE} \
    PKG_CONFIG_PATH=${TOP}/sysroot_tmp/lib/pkgconfig/ \
    EXTRA_CFLAGS="-I${TOP}/sysroot_tmp/include -L${TOP}/sysroot_tmp/lib \
    -L${TOP}/sysroot_tmp/lib64 ${ARCH_FLAG}" NO_LIBPERL=1 NO_LIBPYTHON=1 \
    NO_LIBNUMA=1 NO_LIBAUDIT=1 NO_LIBCRYPTO=1 NO_JVMTI=1 NO_SDT=1 \
    NO_LZMA=1 NO_LIBZSTD=1 NO_LIBCAP=1 NO_LIBBABELTRACE=1 NO_LIBPFM4=1 WERROR=0 \
    make VF=1
}

preprocess
build_zlib
build_elfutils
build_traceevent
build_tracefs
build_slang
copy_library
enable_features
build_perf
