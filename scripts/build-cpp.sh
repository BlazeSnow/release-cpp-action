#!/usr/bin/env bash
# 构建 Cpp 程序（Linux；macOS 使用 build-cpp-macos.sh，Windows 使用 build-cpp.ps1）
# 读取环境变量：
#   PROGRAM_NAME     程序名称（必填）
#   PROGRAM_VERSION  版本号（必填，进入产物文件名）
#   BASE_DIR         BASE 目录（默认 .）
#   CXX_STANDARD     C++ 标准（仅直接编译模式，编号或完整 -std 值，默认 17）
# 产物输出到 <BASE_DIR>/dist/<name>-<version>-linux-<arch>
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

if [ "$(uname -s)" != "Linux" ]; then
	echo "::error::本脚本仅支持 Linux，当前系统: $(uname -s)"
	exit 1
fi

arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
case "$arch" in
	x86_64|amd64) arch="x64" ;;
	aarch64|arm64) arch="arm64" ;;
esac

dist_dir="$base_dir/dist"
output="$dist_dir/${name}-${version}-linux-${arch}"
mkdir -p "$dist_dir"

if [ -f "$base_dir/CMakeLists.txt" ]; then
	# CMake 模式：要求 CMake 目标名与程序名称一致
	build_dir="$base_dir/build"
	cmake -S "$base_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$build_dir/bin"
	cmake --build "$build_dir" --config Release --parallel

	built="$build_dir/bin/$name"
	if [ ! -f "$built" ]; then
		# 兜底：项目自定义输出目录或多配置生成器时递归查找
		mapfile -d '' candidates < <(find "$build_dir" -type f -name "$name" -not -path "*/CMakeFiles/*" -print0)
		if [ "${#candidates[@]}" -eq 0 ]; then
			echo "::error::CMake 构建完成但未找到产物: $name"
			exit 1
		fi
		built="${candidates[0]}"
	fi
	mv -f "$built" "$output"
else
	# 直接编译模式：编译 BASE 目录顶层的 Cpp 源文件（不递归）
	mapfile -d '' sources < <(find "$base_dir" -maxdepth 1 -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \) -print0)
	if [ "${#sources[@]}" -eq 0 ]; then
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

	# 静态链接 C++ 运行库，产物在旧系统上也能运行
	link_flags=(-static-libstdc++ -static-libgcc)
	"$compiler" -std="$std" -O2 -o "$output" "${link_flags[@]}" "${sources[@]}"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "artifact-path=$output" >> "$GITHUB_OUTPUT"
fi
echo "构建完成: $output"
