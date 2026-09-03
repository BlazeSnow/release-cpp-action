#!/bin/zsh
# 构建 Cpp 程序（macOS）
# zsh 为 macOS 默认 shell；自带 bash 3.2 过老，不维护 bash 版本
# 读取环境变量：
#   PROGRAM_NAME     程序名称（必填）
#   PROGRAM_VERSION  版本号（必填，进入产物文件名）
#   BASE_DIR         BASE 目录（默认 .）
#   CXX_STANDARD     C++ 标准（仅直接编译模式，编号或完整 -std 值，默认 17）
# 产物输出到 <BASE_DIR>/dist/<name>-<version>-macos-<arch>
set -euo pipefail

name="${PROGRAM_NAME:?缺少 PROGRAM_NAME}"
version="${PROGRAM_VERSION:?缺少 PROGRAM_VERSION}"
# ref 名可能含 /（如 PR 触发时的 <PR 号>/merge），替换为 - 保证产物名合法
version="${version//\//-}"
base_dir="${BASE_DIR:-.}"
# 兼容 Windows 风格的反斜杠路径
base_dir="${base_dir//\\//}"
# C++ 标准：编号（如 17）或完整 -std 值（如 gnu++20），默认 17
std="${CXX_STANDARD:-17}"
case "$std" in
	c++*|gnu++*) ;;
	*) std="c++$std" ;;
esac

if [ ! -d "$base_dir" ]; then
	echo "::error::BASE 目录不存在: $base_dir"
	exit 1
fi

arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
case "$arch" in
	x86_64|amd64) arch="x64" ;;
	aarch64|arm64) arch="arm64" ;;
esac

dist_dir="$base_dir/dist"
output="$dist_dir/${name}-${version}-macos-${arch}"
mkdir -p "$dist_dir"

if [ -f "$base_dir/CMakeLists.txt" ]; then
	# CMake 模式：要求 CMake 目标名与程序名称一致
	build_dir="$base_dir/build"
	cmake -S "$base_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$build_dir/bin"
	cmake --build "$build_dir" --config Release --parallel

	built="$build_dir/bin/$name"
	if [ ! -f "$built" ]; then
		# 兜底：递归 glob 查找普通文件，排除 CMakeFiles；zsh 数组下标从 1 开始
		candidates=("$build_dir"/**/"$name"(N.))
		candidates=("${(@)candidates:#*CMakeFiles*}")
		if [ "${#candidates}" -eq 0 ]; then
			echo "::error::CMake 构建完成但未找到产物: $name"
			exit 1
		fi
		built="${candidates[1]}"
	fi
	mv -f "$built" "$output"
else
	# 直接编译模式：编译 BASE 目录顶层的 Cpp 源文件（不递归）
	# (N.) 限定符：无匹配时展开为空，且只取普通文件
	sources=("$base_dir"/*.cpp(N.) "$base_dir"/*.cc(N.) "$base_dir"/*.cxx(N.))
	if [ "${#sources}" -eq 0 ]; then
		echo "::error::$base_dir 下既无 CMakeLists.txt 也无 Cpp 源文件（*.cpp/*.cc/*.cxx）"
		exit 1
	fi

	if command -v c++ >/dev/null 2>&1; then
		compiler="c++"
	elif command -v g++ >/dev/null 2>&1; then
		compiler="g++"
	else
		echo "::error::未找到 C++ 编译器（c++/g++）"
		exit 1
	fi

	# macOS 不支持静态链接 libstdc++，动态链接
	"$compiler" -std="$std" -O2 -o "$output" "${sources[@]}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "artifact-path=$output" >> "$GITHUB_OUTPUT"
fi
echo "构建完成: $output"
