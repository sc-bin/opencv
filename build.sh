#!/bin/bash

# 指定交叉编译器路径
PATH="/opt/toolchain/Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V3.0.2/bin/:${PATH}"
# 指定目标rootfs
PATH_ROOTFS="/work/walnutpi-build/.tmp/rootfs-build/xcam_debian13_server"

set -e

OPENCV_SRC=$(pwd)
CONTRIB_SRC=./opencv_contrib-4.10.0
BUILD_DIR=build
INSTALL_DIR=$(pwd)/install

# ============================================================================
# 清理并创建目录
# ============================================================================
rm -rf ${BUILD_DIR} ${INSTALL_DIR}
mkdir -p ${BUILD_DIR}

cd ${BUILD_DIR}

# 自动检测 Python 版本
find_python_version() {
    local rootfs_path="$1"

    # 从头文件路径检测版本
    local include_dir="${rootfs_path}/usr/include"
    if [ -d "$include_dir" ]; then
        for dir in $(ls -1 "$include_dir" 2>/dev/null | grep -E "^python[0-9]+\.[0-9]+"); do
            echo "${dir#python}" # 移除 "python" 前缀，返回版本号
            return 0
        done
    fi

    # 从可执行文件获取版本
    if [ -x "${rootfs_path}/usr/bin/python3" ]; then
        local py_version=$("${rootfs_path}/usr/bin/python3" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$py_version" ]; then
            echo "$py_version"
            return 0
        fi
    fi

    # 默认版本
    echo "3.11"
}

# 获取各个组件的路径
PYTHON_VERSION=$(find_python_version "$PATH_ROOTFS")
NUMPY_INCLUDE_PATH="${PATH_ROOTFS}/usr/lib/python3/dist-packages/numpy/_core/include"
NUMPY_VERSION=$(grep -oE '([0-9]+\.[0-9]+)' "${NUMPY_INCLUDE_PATH}/numpy/version.py" 2>/dev/null || echo "1.21")

# ============================================================================
# 执行 CMake 配置
# ============================================================================
cmake ${OPENCV_SRC} \
    -DCMAKE_TOOLCHAIN_FILE=../toolchain-riscv64-k230.cmake \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON 

# 检查 CMake 配置是否成功
if [ $? -ne 0 ]; then
    echo "错误: CMake 配置失败"
    exit 1
fi
# ============================================================================
# 编译和安装
# ============================================================================
make -j$(nproc) VERBOSE=1
make install

echo "========================================"
echo "编译完成！安装路径: ${INSTALL_DIR}"
echo "========================================"
