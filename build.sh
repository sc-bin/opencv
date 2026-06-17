#!/bin/bash

# 指定交叉编译器路径
PATH="/opt/toolchain/Xuantie-900-gcc-linux-6.6.0-glibc-x86_64-V3.0.2/bin/:${PATH}"
# 指定目标rootfs
PATH_ROOTFS="/work/walnutpi-build/.tmp/rootfs-build/cybercam_debian13_server/"

set -e

# 交叉编译 pkg-config 配置：指向目标系统 rootfs 的 .pc 文件
# PKG_CONFIG_SYSROOT_DIR: 将 .pc 文件中的路径前缀映射到 sysroot
# PKG_CONFIG_LIBDIR: 指定 pkg-config 搜索 .pc 文件的路径（替代默认路径）
export PKG_CONFIG_SYSROOT_DIR="${PATH_ROOTFS}"
export PKG_CONFIG_LIBDIR="${PATH_ROOTFS}/usr/lib/riscv64-linux-gnu/pkgconfig:${PATH_ROOTFS}/usr/share/pkgconfig"

OPENCV_SRC=$(pwd)
CONTRIB_SRC=$(pwd)/opencv_contrib-4.10.0
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
PYTHON3_VERSION_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON3_VERSION_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
NUMPY_INCLUDE_PATH="${PATH_ROOTFS}/usr/lib/python3/dist-packages/numpy/_core/include"
NUMPY_VERSION=$(grep -oE '([0-9]+\.[0-9]+)' "${NUMPY_INCLUDE_PATH}/numpy/version.py" 2>/dev/null || echo "1.21")

# ============================================================================
# 执行 CMake 配置
# ============================================================================
cmake ${OPENCV_SRC} \
    -DCMAKE_TOOLCHAIN_FILE=../toolchain-riscv64-k230.cmake \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_opencv_python3=ON \
    -DOPENCV_EXTRA_MODULES_PATH=${CONTRIB_SRC}/modules \
    -DBUILD_opencv_freetype=ON \
    -DWITH_FREETYPE=ON \
    -DFREETYPE_INCLUDE_DIRS="${PATH_ROOTFS}/usr/include/freetype2;${PATH_ROOTFS}/usr/include" \
    -DFREETYPE_LIBRARIES="${PATH_ROOTFS}/usr/lib/riscv64-linux-gnu/libfreetype.so" \
    -DHARFBUZZ_INCLUDE_DIRS="${PATH_ROOTFS}/usr/include/harfbuzz" \
    -DHARFBUZZ_LIBRARIES="${PATH_ROOTFS}/usr/lib/riscv64-linux-gnu/libharfbuzz.so" \
    -DPYTHON3_VERSION_MAJOR=${PYTHON3_VERSION_MAJOR} \
    -DPYTHON3_VERSION_MINOR=${PYTHON3_VERSION_MINOR} \
    -DPYTHON3_EXECUTABLE=/usr/bin/python3 \
    -DPYTHON3_INCLUDE_PATH="${PATH_ROOTFS}/usr/include/python${PYTHON_VERSION};${PATH_ROOTFS}/usr/include/riscv64-linux-gnu/;${PATH_ROOTFS}/usr/include/" \
    -DPYTHON3_INCLUDE_DIR=${PATH_ROOTFS}/usr/include/python${PYTHON_VERSION} \
    -DPYTHON3_LIBRARIES=${PATH_ROOTFS}/usr/lib/riscv64-linux-gnu/libpython${PYTHON_VERSION}.so \
    -DPYTHON3_LIBRARY=${PATH_ROOTFS}/usr/lib/riscv64-linux-gnu/libpython${PYTHON_VERSION}.so \
    -DPYTHON3_NUMPY_INCLUDE_DIRS=${PATH_ROOTFS}/usr/lib/python3/dist-packages/numpy/_core/include \
    -DPYTHON3_PACKAGES_PATH=/usr/local/lib/python${PYTHON_VERSION}/dist-packages \
    -DPYTHON3_NUMPY_VERSION=${NUMPY_VERSION} \
    -DCMAKE_FIND_ROOT_PATH=${PATH_ROOTFS} \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY

# 检查 CMake 配置是否成功
if [ $? -ne 0 ]; then
    echo "错误: CMake 配置失败"
    exit 1
fi
# ============================================================================
# 编译和安装
# ============================================================================
make -j$(nproc) VERBOSE=1

rm -rf ${INSTALL_DIR}
make install DESTDIR=${INSTALL_DIR}

DIST_SO_DIR=${INSTALL_DIR}/usr/local/lib/python${PYTHON_VERSION}/dist-packages/cv2/python-${PYTHON_VERSION}/
# 将DIST_SO_DIR路径下的文件重命名为cv2.cpython-313-riscv64-linux-gnu.so
for file in ${DIST_SO_DIR}*.so; do
    mv "$file" "${DIST_SO_DIR}cv2.cpython-${PYTHON3_VERSION_MAJOR}${PYTHON3_VERSION_MINOR}-riscv64-linux-gnu.so"
done

echo "========================================"
echo "编译完成！安装路径: ${INSTALL_DIR}"
echo "========================================"
