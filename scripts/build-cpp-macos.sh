#!/bin/zsh
# 构建 Cpp 程序（macOS）
# zsh 为 macOS 默认 shell；自带 bash 3.2 过老，不维护 bash 版本
# 读取环境变量：
#   PROGRAM_NAME     程序名称（必填）
#   PROGRAM_VERSION  版本号（必填，进入产物文件名）
#   BASE_DIR         BASE 目录（默认 .）
#   CXX_STANDARD     C++ 标准（仅直接编译模式，编号或完整 -std 值，默认 17）
#   C_STANDARD       C 标准（仅直接编译模式，编号或完整 -std 值，缺省为编译器默认）
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
# C 标准：编号（如 11）或完整 -std 值（如 gnu11），缺省为编译器默认
c_std="${C_STANDARD:-}"
if [ -n "$c_std" ]; then
	case "$c_std" in
		c*|gnu*) ;;
		*) c_std="c$c_std" ;;
	esac
fi

# C 编译器：gcc 优先，回退 cc（macOS 上两者均为 clang）
find_c_compiler() {
	if command -v gcc >/dev/null 2>&1; then
		echo gcc
	elif command -v cc >/dev/null 2>&1; then
		echo cc
	else
		return 1
	fi
}

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
	# 直接编译模式：编译 BASE 目录顶层的 C/C++ 源文件（不递归）
	# (N.) 限定符：无匹配时展开为空，且只取普通文件
	sources=("$base_dir"/*.c(N.) "$base_dir"/*.cpp(N.) "$base_dir"/*.cc(N.) "$base_dir"/*.cxx(N.))
	if [ "${#sources}" -eq 0 ]; then
		echo "::error::$base_dir 下既无 CMakeLists.txt 也无 C/C++ 源文件（*.c/*.cpp/*.cc/*.cxx）"
		exit 1
	fi

	# 按语言分组
	c_sources=()
	cxx_sources=()
	for f in "${sources[@]}"; do
		case "$f" in
			*.c) c_sources+=("$f") ;;
			*) cxx_sources+=("$f") ;;
		esac
	done

	c_std_flags=()
	if [ -n "$c_std" ]; then
		c_std_flags+=(-std="$c_std")
	fi

	if [ "${#cxx_sources}" -eq 0 ]; then
		# 纯 C：C 编译器直接编译链接（macOS 上 gcc/cc 均为 clang，动态链接）
		if ! c_compiler="$(find_c_compiler)"; then
			echo "::error::未找到 C 编译器（gcc/cc）"
			exit 1
		fi
		"$c_compiler" "${c_std_flags[@]}" -O2 -o "$output" "${c_sources[@]}"
	else
		if command -v c++ >/dev/null 2>&1; then
			compiler="c++"
		elif command -v g++ >/dev/null 2>&1; then
			compiler="g++"
		else
			echo "::error::未找到 C++ 编译器（c++/g++）"
			exit 1
		fi

		c_objects=()
		if [ "${#c_sources}" -gt 0 ]; then
			# .c 需由 C 编译器单独编译成 .o（C++ 编译器会把 .c 当 C++ 编译），再与 C++ 源文件一并链接
			if ! c_compiler="$(find_c_compiler)"; then
				echo "::error::未找到 C 编译器（gcc/cc）"
				exit 1
			fi
			obj_dir="$(mktemp -d)"
			for f in "${c_sources[@]}"; do
				obj="$obj_dir/$(basename "$f").o"
				"$c_compiler" "${c_std_flags[@]}" -O2 -c -o "$obj" "$f"
				c_objects+=("$obj")
			done
		fi
		# macOS 不支持静态链接 libstdc++，动态链接
		"$compiler" -std="$std" -O2 -o "$output" "${cxx_sources[@]}" "${c_objects[@]}"
		if [ -n "${obj_dir:-}" ]; then
			rm -rf "$obj_dir"
		fi
	fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "artifact-path=$output" >> "$GITHUB_OUTPUT"
fi
echo "构建完成: $output"
