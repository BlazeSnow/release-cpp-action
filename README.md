# release-cpp-action

[![Test](https://github.com/BlazeSnow/release-cpp-action/actions/workflows/test.yml/badge.svg)](https://github.com/BlazeSnow/release-cpp-action/actions/workflows/test.yml)

构建 Cpp 程序并上传构建产物至 GitHub Release。

在多平台矩阵 workflow 中调用本 Action，即可在每个平台上编译 Cpp 程序，并把产物上传到当前 tag 对应的 GitHub Release。

## 用法

在你自己的仓库中创建 workflow（例如 `.github/workflows/release.yml`）：

```yaml
name: Release

on:
  push:
    tags:
    - 'v*'

permissions:
  contents: write

jobs:
  release:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
    - name: 检出仓库
      uses: actions/checkout@v7

    - name: 构建并上传至 Release
      uses: BlazeSnow/release-cpp-action@v1
      with:
        name: myapp
        base-dir: src
```

打上 `v1.0.0` 标签推送后，三个平台会分别编译 `src` 目录下的程序，并把产物上传到该 tag 的 Release：

- `myapp-linux-x64`
- `myapp-macos-arm64`
- `myapp-windows-x64.exe`

> 主版本标签（`v1`）只跟随正式版发布，预发布阶段可先用完整版本号引用，如 `BlazeSnow/release-cpp-action@v1.0-beta.1`。

## 输入参数

| 参数 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `name` | 是 | - | 程序名称，用作编译目标名与产物文件名前缀 |
| `base-dir` | 否 | `.` | BASE 目录，即 Cpp 源码所在目录 |

## 输出参数

| 参数 | 说明 |
| --- | --- |
| `artifact-path` | 构建产物路径 |

## 构建规则

BASE 目录下存在 `CMakeLists.txt` 时使用 CMake 构建（Release 模式），要求 CMake 目标名与 `name` 一致；否则直接调用编译器编译该目录下的 `*.cpp` / `*.cc` / `*.cxx`（C++17，`-O2`，不递归子目录）。

产物输出到 `<base-dir>/dist/`，命名为 `<name>-<os>-<arch>[.exe]`（如 `myapp-linux-x64`、`myapp-macos-arm64`、`myapp-windows-x64.exe`）。Windows 产物静态链接运行库，可独立运行；Linux 产物静态链接 C++ 标准库；macOS 产物动态链接。

## Release 上传规则

- 仅当 workflow 由 tag 触发时上传，其他触发（push 分支 / PR / 手动）自动跳过，便于日常测试。
- Release 不存在时自动创建；tag 含 `-`（如 `v1.0-beta.1`）时按预发布版本创建。
- 使用 `--clobber` 上传，重复执行会覆盖同名产物；多平台矩阵的各个任务向同一个 Release 上传各自平台的产物。

## 本仓库发版

1. 更新 `VERSION` 与 `CHANGELOG.md`
2. 运行 `./tag.ps1` 创建并推送 tag
3. `release.yml` 自动校验 tag 与 `VERSION` 一致、创建 GitHub Release；正式版还会更新主版本标签（如 `v1.0.0` → `v1`），预发布版本跳过

## License

[MIT](LICENSE) © [BlazeSnow](https://github.com/BlazeSnow)
