#!/usr/bin/env bash
# 测试用：运行构建产物并校验输出
# 读取环境变量：ARTIFACT  产物路径
set -euo pipefail

artifact="${ARTIFACT:?缺少 ARTIFACT}"
echo "产物: $artifact"
output="$("$artifact")"
echo "输出: $output"
if [ "$output" != "Hello World!" ]; then
	echo "::error::产物输出与预期不符: $output"
	exit 1
fi
