#!/usr/bin/env bash
# 校验触发 tag 与 VERSION 文件一致，防止忘记更新 VERSION
set -euo pipefail

version="$(head -n 1 VERSION | tr -d ' \t\r\n')"
ref="${GITHUB_REF_NAME:-}"
if [ "$version" != "$ref" ]; then
	echo "::error::tag ($ref) 与 VERSION ($version) 不一致"
	exit 1
fi
