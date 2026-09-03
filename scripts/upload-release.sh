#!/usr/bin/env bash
# 上传构建产物至当前 tag 对应的 GitHub Release
# 读取环境变量：
#   GH_TOKEN / GH_REPO  gh CLI 凭据与仓库（由 action.yml 注入）
#   TAG_NAME            目标 Release 的 tag
#   BASE_DIR            BASE 目录（产物位于 <BASE_DIR>/dist/）
set -euo pipefail

tag="${TAG_NAME:?缺少 TAG_NAME}"
base_dir="${BASE_DIR:-.}"
# 兼容 Windows 风格的反斜杠路径
base_dir="${base_dir//\\//}"

shopt -s nullglob
files=("$base_dir"/dist/*)
if [ "${#files[@]}" -eq 0 ]; then
	echo "::error::未找到构建产物：$base_dir/dist/"
	exit 1
fi

if ! gh release view "$tag" >/dev/null 2>&1; then
	# tag 含 '-'（如 v1.0-beta.1）判定为预发布，与仓库自身 release.yml 规则一致
	extra=''
	if [ "${tag#*-}" != "$tag" ]; then
		extra='--prerelease'
	fi
	# 多平台矩阵并发创建 Release 时可能竞争，失败大概率是其他矩阵任务已创建
	gh release create "$tag" --title "$tag" --generate-notes $extra || true
fi

gh release upload "$tag" "${files[@]}" --clobber
echo "已上传至 Release $tag: ${files[*]}"
