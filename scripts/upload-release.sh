#!/usr/bin/env bash
# 上传构建产物至 GitHub Release
# 读取环境变量：
#   GH_TOKEN / GH_REPO  gh CLI 凭据与仓库（由 action.yml 注入）
#   RELEASE             true 时才上传（开关判断必须在脚本内）
#   TAG_NAME            目标 Release 的 tag
#   BASE_DIR            BASE 目录（产物位于 <BASE_DIR>/dist/）
#   EXTRA_FILES         额外上传的文件，每行一个（相对于 BASE 目录，可为空）
#   RELEASE_BODY        Release 说明正文（仅创建 Release 时使用，可为空）
#   RELEASE_NAME        自定义 Release 标题（默认与 tag 同名，可为空）
#   PRERELEASE          true 时标记为预发布版本
#   DRAFT               true 时存为草稿
set -euo pipefail

# composite 输入在 if 表达式里是字符串（'false' 也为真），布尔开关不能写在步骤 if 上
if [ "${RELEASE:-false}" != "true" ]; then
	echo "release 参数未开启，跳过上传"
	exit 0
fi

tag="${TAG_NAME:?缺少 TAG_NAME}"
base_dir="${BASE_DIR:-.}"
# 兼容 Windows 风格的反斜杠路径
base_dir="${base_dir//\\//}"
title="${RELEASE_NAME:-$tag}"

shopt -s nullglob
files=("$base_dir"/dist/*)
if [ "${#files[@]}" -eq 0 ]; then
	echo "::error::未找到构建产物：$base_dir/dist/"
	exit 1
fi

# 额外文件：每行一个，相对于 BASE 目录（不支持目录，直接上传原始文件）
if [ -n "${EXTRA_FILES:-}" ]; then
	while IFS= read -r line; do
		# 去除行首尾空白与 CR
		line="${line%"${line##*[![:space:]]}"}"
		line="${line#"${line%%[![:space:]]*}"}"
		[ -n "$line" ] || continue
		f="$base_dir/$line"
		if [ -d "$f" ]; then
			echo "::error::extra-files 不支持目录: $line"
			exit 1
		fi
		if [ ! -f "$f" ]; then
			echo "::error::extra-files 文件不存在: $line"
			exit 1
		fi
		files+=("$f")
	done <<< "$EXTRA_FILES"
fi

if ! gh release view "$tag" >/dev/null 2>&1; then
	create_args=(--title "$title")
	if [ -n "${RELEASE_BODY:-}" ]; then
		create_args+=(--notes "$RELEASE_BODY")
	else
		create_args+=(--generate-notes)
	fi
	if [ "${PRERELEASE:-false}" = "true" ]; then
		create_args+=(--prerelease)
	fi
	if [ "${DRAFT:-false}" = "true" ]; then
		create_args+=(--draft)
	fi
	# 多平台矩阵并发创建 Release 时可能竞争，失败大概率是其他矩阵任务已创建
	gh release create "$tag" "${create_args[@]}" || true
fi

gh release upload "$tag" "${files[@]}" --clobber
echo "已上传至 Release $tag: ${files[*]}"
