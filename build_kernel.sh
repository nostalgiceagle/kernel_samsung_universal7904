#!/bin/bash

set -euo pipefail
[[ -n "${3:-}" ]] && set "-$3"
trap "echo KeyboardInterrupt!; exit 1" INT

RED='31m'
GREEN='32m'
WHITE='97m'
NC='[0m'
BOLD='[1;'
DEVICE=$1
DTB=$2
DTB_YN=$([[ "$DTB" == "dtb" ]] && echo " with DTB" || echo " without DTB")
ROOT_DIR=$(pwd)

git submodule update --init --recursive
cd KernelSU-Next/
COMMIT_TAG=$(git describe --tags)
cd ..

LOCALVER="-KSUN-${COMMIT_TAG}"

clean() {
    echo -e "\n\e${BOLD}${WHITE}========="
    echo -e "| CLEAN |"
    echo -e "=========\e${NC}\n"

    cd ${ROOT_DIR}/
    make clean -j4 2>&1 | tee log_clean.log
    rm -rf include/generated/ include/config/
}

defconfig() {
    echo -e "\n\e${BOLD}${WHITE}============="
    echo -e "| DEFCONFIG |"
    echo -e "=============\e${NC}\n"

    make LOCALVERSION=\"${LOCALVER}\" ARCH=arm64 -j4 "exynos7885-${DEVICE}_oneui_defconfig" 2>&1 | tee "log_${DEVICE}_defconfig.log"
}

kernel() {
    echo -e "\n\e${BOLD}${WHITE}=========="
    echo -e "| KERNEL |"
    echo -e "==========\e${NC}\n"

    make LOCALVERSION=\"${LOCALVER}\" ARCH=arm64 -j4 2>&1 | tee log_${DEVICE}_kernel.log
}

zip_kernel() {
    echo -e "\n\e${BOLD}${GREEN}===================="
    echo -e "| Build succeeded! |"
    echo -e "====================\e${NC}\n"

    KERNEL_VERSION=$(grep UTS_RELEASE include/generated/utsrelease.h | cut -d'"' -f2 | sed 's/+*$//')
    echo -e "\e[${GREEN}Kernel version: ${KERNEL_VERSION}"
    
    cp arch/arm64/boot/Image AnyKernel3/Image
    FILES=(
        "Image"
        "version"
        "META-INF/com/google/android/update-binary"
        "META-INF/com/google/android/updater-script"
        "tools/ak3-core.sh"
        "tools/busybox"
        "tools/magiskboot"
        "tools/tweaks.zip"
        "anykernel.sh"
    )
    
    if [ "${DTB}" == "dtb" ]; then
        echo -e "\n\e${BOLD}${WHITE}======="
        echo -e "| DTB |"
        echo -e "=======\e${NC}\n"

        make ARCH=arm64 -j4 dtb.img 2>&1 | tee log_dtb.log
        cp arch/arm64/boot/dtb.img AnyKernel3/dtb.img

        FILES+=("dtb.img")
    fi
    
    sed -i "1s/.*/${KERNEL_VERSION}/" AnyKernel3/version

    ZIPNAME="$(tr '[:lower:]' '[:upper:]' <<< ${DEVICE:0:1})${DEVICE:1} ${KERNEL_VERSION}.zip"

    echo -e "\n\e${BOLD}${WHITE}=============="
    echo -e "| ZIP KERNEL |"
    echo -e "==============\e${NC}\n"
    cd AnyKernel3/ 
    zip -r9 "${ZIPNAME}" "${FILES[@]}"
    mv "${ZIPNAME}" "${ROOT_DIR}/"
    cd ${ROOT_DIR}/

    echo -e "\e${BOLD}${GREEN}Kernel zip: $PWD/${ZIPNAME}"
    echo -e "Done\e${NC}"

    sed -i "1s/.*/KERNELVERSION/" ${ROOT_DIR}/AnyKernel3/version
}

main() {
    echo -e "\nKernelSU-Next ${COMMIT_TAG}"
    start_time=$(date +%s)

    clean
    defconfig
    kernel

    end_time=$(date +%s)
    if [ -s "arch/arm64/boot/Image" ]; then
        zip_kernel
    else
        echo -e "\n\e${BOLD}${RED}=============================================="
        echo -e "| Build failed, reason should be above this! |"
        echo -e "==============================================\e${NC}\n"
    fi
    clean
    elapsed_time=$((end_time - start_time))
    echo -e "Took $(printf '%02d minutes, %02d seconds' $((elapsed_time%3600/60)) $((elapsed_time%60)))\n"
}

main