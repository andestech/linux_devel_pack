#!/bin/bash

help()
{
  echo "BUILD:"
  echo "    $0 -build XXXX-linux-        # build for riscv architectute"
  echo "INSTALL:"
  echo "    $0 -install                  # install to current path ./install/"
  echo "    $0 -install xxx/xxx/xxx      # install to specific path xxx/xxx/xxx"
  echo "CLEAN:"
  echo "    $0 -clean"
  exit 1;
}

error_msg()
{
  printf "\nError: $1. Please given the correct toolchain prefix.\n\n"
  help
}

build()
{
  if [ -z $2 ]; then
    error_msg "Empty argument"
  else
    CROSS_COMPILE=$2
    which ${CROSS_COMPILE}gcc
    if [ "$?" -ne ""0 ]; then
      error_msg "Cannot find the gcc"
    fi
  fi

  make ${DEFCONFIG} | tee -a ${LOG_FILE}
  sed -e "s#CROSS_COMPILER_PREFIX=.*#CROSS_COMPILER_PREFIX=\"$CROSS_COMPILE\"#" -i .config

  make 2>&1 | tee -a ${LOG_FILE}
}

install()
{
  if [ -z $2 ]; then
    INSTALL_PATH=`cat .config | grep ^CONFIG_PREFIX | awk -F "=" '{print $2}'`
  else
    INSTALL_PATH=$2
  fi

  make CONFIG_PREFIX=${INSTALL_PATH} install 2>&1 | tee -a ${LOG_FILE}

  echo Install path is : ${INSTALL_PATH}
}

clean()
{
  make clean 2>&1 | tee -a ${LOG_FILE}
}

DEFCONFIG=andes_defconfig
LOG_FILE=build_busybox.log

if [ $# -eq 0 ]; then
  help
fi

case "$1" in
  "-build")
  build $*
  ;;
  "-install")
  install $*
  ;;
  "-clean")
  clean $*
  ;;
  *)
  echo "Nothing to do. Unknown option: $1"
  ;;
esac
