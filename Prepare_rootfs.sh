#!/usr/bin/env bash

# === check env, must using bash to run this script ===
execute_env=`ps -p $$`
which_bash=`which bash`
if [ "${execute_env##* }" != 'bash' ]; then
    echo "!! Error: Please using \"$which_bash\" to run or execute with ./Prepare_rootfs.sh , not \"${execute_env##* }\""
    exit
fi

# === argurment  passing ===
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
        --cpu=*)
            CPU=${var#*=}
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
             echo "--arch=rv[32|64][v5|v5d]         Specify the architecture. (Default: rv32v5d)"
             echo "--cpu=[25|45]  Specify the cpu. (Default 25)"
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
CPU=${CPU:=25}

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
        tar cfz rootfs.tgz ./rootfs
        tar cfz busybox.tgz ./busybox
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
if [ "${CPU}" != "25" ] && [ "${CPU}" != "45" ] ; then
    echo ""
    echo "!! Error: please check if the specified cpu is [25|45]"
    echo ""
    exit
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
    declare -A dict=(
        [rv32v5]=lib32/ilp32
        [rv32v5d]=lib32/ilp32d
        [rv64v5]=lib64/lp64
        [rv64v5d]=lib64/lp64d
    )

    declare -A dict2=(
        [45]=/mtune-andes-45-series
    )

    for library in "${!dict[@]}"
    do
        if [ "$library" == "$ARCH" ]; then
            src_library_name=${dict[$library]}
            dest_name=${dict[$library]}
        fi
    done

    for series in "${!dict2[@]}"
    do
        if [ "$series" == "$CPU" ]; then
            src_library_name="$src_library_name${dict2[$series]}"
        fi
     done

    CROSS_FOLDER=$TOOLCHAIN_PATH
    DISK_PATH=$RAMDISK_PATH/rootfs/disk
    sysroot_lib=sysroot/lib
    sysroot_liby=sysroot/$src_library_name
    sysroot_usr_liby=sysroot/usr/$src_library_name
    sysroot_sbin=sysroot/sbin
    sysroot_usr_bin=sysroot/usr/bin
    sysroot_usr_sbin=sysroot/usr/sbin

    echo "start to copy library"
    echo "copy library from $src_library_name to $dest_name"
    echo "cp -arf $CROSS_FOLDER/$sysroot_lib/* $DISK_PATH/lib/"
    cp -arf $CROSS_FOLDER/$sysroot_lib/* $DISK_PATH/lib/
    echo "cp -arf $CROSS_FOLDER/$sysroot_liby/* $DISK_PATH/$dest_name/"
    cp -arf $CROSS_FOLDER/$sysroot_liby/* $DISK_PATH/$dest_name
    rm -f $DISK_PATH/$dest_name/*.a
    echo "cp -arf $CROSS_FOLDER/$sysroot_usr_liby/* $DISK_PATH/usr/$dest_name/"
    cp -arf $CROSS_FOLDER/$sysroot_usr_liby/* $DISK_PATH/usr/$dest_name/
    rm -f $DISK_PATH/usr/$dest_name/*.a
    echo "cp -arf $CROSS_FOLDER/$sysroot_sbin/* $DISK_PATH/sbin/"
    cp -arf $CROSS_FOLDER/$sysroot_sbin/* $DISK_PATH/sbin/
    echo "cp -arf $CROSS_FOLDER/$sysroot_usr_bin/* $DISK_PATH/usr/bin/"
    cp -arf $CROSS_FOLDER/$sysroot_usr_bin/* $DISK_PATH/usr/bin/
    echo "cp -arf $CROSS_FOLDER/$sysroot_usr_sbin/* $DISK_PATH/usr/sbin/"
    cp -arf $CROSS_FOLDER/$sysroot_usr_sbin/* $DISK_PATH/usr/sbin/
    if [ ${CPU} == "25" ]; then
        rm -rf $DISK_PATH/$dest_name/mtune*
        rm -rf $DISK_PATH/usr/$dest_name/mtune*
    fi
    if [ ${CPU} != "25" ]; then
        ln -fs . $DISK_PATH/$src_library_name
    fi
    echo "===== copy library done ====="
}

create_ld_link()
{
    echo "===== create link start ====="
    declare -A dict3=(
        [rv32v5-45]=ld-linux-riscv32-ilp32_andes-45-series.so.1
        [rv32v5d-45]=ld-linux-riscv32-ilp32d_andes-45-series.so.1
        [rv64v5-45]=ld-linux-riscv64-lp64_andes-45-series.so.1
        [rv64v5d-45]=ld-linux-riscv64-lp64d_andes-45-series.so.1
    )

    declare -A dict4=(
        [rv32v5d]=ld-linux-riscv32-ilp32d.so.1
        [rv32v5]=ld-linux-riscv32-ilp32.so.1
        [rv64v5]=ld-linux-riscv64-lp64.so.1
        [rv64v5d]=ld-linux-riscv64-lp64d.so.1
    )

    for target_item in "${!dict3[@]}"
    do
        if [ "$target_item" == "$ARCH-$CPU" ]; then
            target_link=${dict3[$target_item]}
        fi
    done
    for link_item in "${!dict4[@]}"
    do
        if [ "$link_item" == "$ARCH" ]; then
            link_name=${dict4[$link_item]}
        fi
    done

    if [ "$CPU" != "25"  ]; then
        echo "create ld link : $link_name -> $target_link"
        ln -fs $target_link $DISK_PATH/lib/$link_name
    fi
    echo "===== create link done ====="
}

strip_program()
{
    cd $DISK_PATH
    for line in $(find . -name *.so*); do
        $STRIP --strip-unneeded --preserve-dates $line
    done
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
create_ld_link
strip_program
build_busybox
echo "===== Prepar root fild system done! ======"
