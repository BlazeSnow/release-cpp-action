#!/usr/bin/env bash
# 正式版（tag 不含 -）强制更新主版本标签（如 v1.0.0 -> v1）；预发布版本跳过
set -euo pipefail

ref="${GITHUB_REF_NAME:?缺少 GITHUB_REF_NAME}"
sha="${GITHUB_SHA:?缺少 GITHUB_SHA}"

if [[ "$ref" == *-* ]]; then
	echo "$ref 为预发布版本，不更新主版本标签"
	exit 0
fi

major="${ref%%.*}"
if [ "$major" = "$ref" ]; then
	echo "tag 不含次版本号，跳过主版本标签更新"
	exit 0
fi

git tag -f "$major" "$sha"
git push --force origin "refs/tags/$major"
