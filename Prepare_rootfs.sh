#!/bin/bash
# === argurment passing ===
for var in $@; do
    case "$var" in
        --toolchain_path=*)
	    TOOLCHAIN_PATH=${var#*=}
	    ;;
        --ramdisk_root_path=*)
            RAMDISK_PATH=${var#*=}
            ;;
        --CROSS_COMPILE=*)
            CROSS_COMPILE=${var#*=}
            ;;
        --tar_file_path=*)
            TAR_PATH=${var#*=}
            ;;
        --arch=*)
            ARCH=${var#*=}
            ;;
        --help)
             echo ""
             echo "[[ help message ]]"
             echo "==== required argument ===="
             echo "--toolchain_path=     Specify a toolchain directory (EX: \$PWD/nds32le-linux-glibc-v5)"
             echo ""
             echo "==== optional arguments ===="
             echo "--CROSS_COMPILE=      riscv[32|64]-linux- (Default: riscv32-linux-)"
             echo "--ramdisk_root_path=  Specify a dir to contain files for building root file system. (Default: \$PWD/ramdisk)"
	     echo "--tar_file_path=      Specify a dir that contains busybox and rootfs directory or tarball(tgz). (Default: \$PWD)"
             echo "--arch=v5/v5d         Specify the architecture. (Default: v5d)"
             echo ""
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
RAMDISK_PATH=${RAMDISK_PATH:=`pwd`/ramdisk}
TAR_PATH=${TAR_PATH:=`pwd`}
CROSS_COMPILE=${CROSS_COMPILE:=riscv32-linux-}
CROSS_FILENAME=${CROSS_COMPILE%-}
ARCH=${ARCH:=rv32v5d}

# === export path ===
export PATH=${TOOLCHAIN_PATH}/bin:$PATH
export CC=${CROSS_COMPILE}gcc
export CXX=${CROSS_COMPILE}g++
export AR=${CROSS_COMPILE}ar
export AS=${CROSS_COMPILE}as
export RANLIB=${CROSS_COMPILE}ranlib
export LD=${CROSS_COMPILE}ld
export STRIP=${CROSS_COMPILE}strip

if [ "${TOOLCHAIN_PATH}" = "" ]; then
    echo ""
    echo "!! Error: The toolchain path is not specified. !!"
    echo "!! Error: Please specify a toolchain path. (EX: \$PWD/nds32le-linux-glibc-v5)  !!"
    echo ""
    exit
fi

if [ ! -f "$TAR_PATH/busybox.tgz" ]  || [ ! -f "$TAR_PATH/rootfs.tgz" ]; then
    if [ ! -d "$TAR_PATH/busybox" ]  || [ ! -d "$TAR_PATH/rootfs" ]; then
        echo ""
        echo "!! Error: Can not find busybox.tgz or rootfs.tgz. !!"
        echo "!! Error: Please specify a dir that contains busybox.tgz and rootfs.tgz. !!"
        echo ""
        exit
    else
        pushd $TAR_PATH
        tar cvfz rootfs.tgz ./rootfs
        tar cvfz busybox.tgz ./busybox
	popd
    fi
fi

# === check gcc ===
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
else
    export LDFLAGS="-march=${ARCH}"
    export CFLAGS="-march=${ARCH}"
fi

create_root()
{
    mkdir -p $RAMDISK_PATH
    cd $RAMDISK_PATH
    tar xfz $TAR_PATH/rootfs.tgz
    tar xfz $TAR_PATH/busybox.tgz
    echo "===== decompress files done. ====="
}

copy_library()
{
    # check and library path
    multi_lib_path=`$CC -print-multi-lib`
    libc_path=`$CC -print-file-name=libc.a`
    for line in $multi_lib_path; do
        if [ "$line" == ".;" ]; then
            continue
        else
		if [ "$(echo ${ARCH} | grep v5d)y" = "y" ]; then
                search_name='imacxv5'
            else
                search_name='imafdcxv5'
            fi

            echo $line | grep -q "$search_name"

            if [ "$?" -eq ""0 ]; then
                library_path=${libc_path%/usr/*}
                library_name=${line%;@*}
                echo $library_path
                echo $library_name
            else
                continue
            fi
        fi
    done

    CROSS_FOLDER=$TOOLCHAIN_PATH/$CROSS_FILENAME
    DISK_PATH=$RAMDISK_PATH/rootfs/disk
    sysroot_lib=sysroot/lib
    sysroot_liby=sysroot/$library_name
    sysroot_usr_liby=sysroot/usr/$library_name
    sysroot_sbin=sysroot/sbin
    sysroot_usr_bin=sysroot/usr/bin
    sysroot_usr_sbin=sysroot/usr/sbin

    echo "start to copy library"
    echo "cp -arf $CROSS_FOLDER/$sysroot_lib/* $DISK_PATH/lib/"
    cp -arf $CROSS_FOLDER/$sysroot_lib/* $DISK_PATH/lib/
    echo "cp -arf $CROSS_FOLDER/$sysroot_liby/* $DISK_PATH/$library_name/"
    cp -arf $CROSS_FOLDER/$sysroot_liby/* $DISK_PATH/$library_name/
    rm -f $DISK_PATH/$library_name/*.a
    echo "cp -arf $CROSS_FOLDER/$sysroot_usr_liby/* $DISK_PATH/usr/$library_name/"
    cp -arf $CROSS_FOLDER/$sysroot_usr_liby/* $DISK_PATH/usr/$library_name/
    rm -f $DISK_PATH/usr/$library_name/*.a
    echo "cp -arf $CROSS_FOLDER/lib/* $DISK_PATH/$library_name/"
    cp -arf $CROSS_FOLDER/lib/* $DISK_PATH/$library_name/
    echo "cp -arf $CROSS_FOLDER/$sysroot_sbin/* $DISK_PATH/sbin/"
    cp -arf $CROSS_FOLDER/$sysroot_sbin/* $DISK_PATH/sbin/
    echo "cp -arf $CROSS_FOLDER/$sysroot_usr_bin/* $DISK_PATH/usr/bin/"
    cp -arf $CROSS_FOLDER/$sysroot_usr_bin/* $DISK_PATH/usr/bin/
    echo "cp -arf $CROSS_FOLDER/$sysroot_usr_sbin/* $DISK_PATH/usr/sbin/"
    cp -arf $CROSS_FOLDER/$sysroot_usr_sbin/* $DISK_PATH/usr/sbin/
    echo "===== copy library done! ====="
}

strip_program()
{
    $STRIP --strip-unneeded $DISK_PATH/lib/*
    $STRIP --strip-unneeded $DISK_PATH/$library_name/*
    echo "===== strip program done! ====="
}

build_busybox(){
    cd $RAMDISK_PATH/busybox
    echo "./build_busybox.sh -build $CROSS_COMPILE"
    ./build_busybox.sh -clean
    ./build_busybox.sh -build $CROSS_COMPILE
    ./build_busybox.sh -install $DISK_PATH
}

# ===== Preparing root file system =====
create_root
copy_library
strip_program
build_busybox
echo "===== Prepar root fild system done! ======"
