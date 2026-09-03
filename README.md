# release-cpp-action

构建 Cpp 程序并上传构建产物至 GitHub Release。

在多平台矩阵 workflow 中调用本 Action，即可在每个平台上编译 Cpp 程序，并把产物上传到当前 tag 对应的 GitHub Release。

> **注意**：项目目前处于测试阶段，尚未发布 v1 正式版，`@v1` 引用暂不可用，请先使用 `@main`。

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
        os: [ubuntu-latest, ubuntu-24.04-arm, macos-latest, macos-26-intel, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
    - name: 检出仓库
      uses: actions/checkout@v7

    - name: 构建并上传至 Release
      uses: BlazeSnow/release-cpp-action@v1
      with:
        name: myapp
        base-dir: src
        release: true
        prerelease: ${{ contains(github.ref_name, '-') }}
```

打上 `v1.0.0` 标签推送后，五个平台会分别编译 `src` 目录下的程序，并把产物上传到该 tag 的 Release：

- `myapp-v1.0.0-linux-x64`
- `myapp-v1.0.0-linux-arm64`
- `myapp-v1.0.0-macos-arm64`
- `myapp-v1.0.0-macos-x64`
- `myapp-v1.0.0-windows-x64.exe`

> macOS 的 `-latest` 标签只有 arm64，x64 需用 `macos-26-intel`（`-large` 后缀为付费 larger runner）；Linux arm64 免费标签为 `ubuntu-24.04-arm`；Windows arm64 镜像（`windows-11-arm`）无 C++ 工具链，暂不支持。

## 输入参数

| 参数           | 必填 | 默认值         | 说明                                                     |
| -------------- | ---- | -------------- | -------------------------------------------------------- |
| `name`         | 是   | -              | 程序名称，用作编译目标名与产物文件名前缀                 |
| `base-dir`     | 否   | `.`            | BASE 目录，即 Cpp 源码所在目录                           |
| `release`      | 否   | `false`        | 是否上传构建产物至 GitHub Release                        |
| `extra-files`  | 否   | -              | 额外上传至 Release 的文件，每行一个（相对于 `base-dir`） |
| `release-body` | 否   | 自动生成       | Release 说明正文（仅在自动创建 Release 时使用）          |
| `release-name` | 否   | tag            | 自定义 Release 标题                                      |
| `prerelease`   | 否   | `false`        | 将 Release 标记为预发布版本                              |
| `draft`        | 否   | `false`        | 将 Release 存为草稿，不直接发布                          |
| `tag`          | 否   | 当前 ref 名称  | 目标 Release 的 tag（显式传入后非 tag 触发也会上传）     |
| `token`        | 否   | `github.token` | GitHub Token（用于创建/上传 Release）                    |

## 输出参数

| 参数            | 说明                                       |
| --------------- | ------------------------------------------ |
| `artifact-path` | 构建产物路径                               |
| `version`       | 版本号（`tag` 输入，缺省为当前 ref 名称）  |

## 构建规则

BASE 目录下存在 `CMakeLists.txt` 时使用 CMake 构建（Release 模式），要求 CMake 目标名与 `name` 一致；否则直接调用编译器编译该目录下的 `*.cpp` / `*.cc` / `*.cxx`（C++17，`-O2`，不递归子目录）。

产物输出到 `<base-dir>/dist/`，命名为 `<name>-<version>-<os>-<arch>[.exe]`（如 `myapp-v1.0.0-linux-x64`、`myapp-v1.0.0-macos-arm64`、`myapp-v1.0.0-windows-x64.exe`）。版本号取 `tag` 参数（缺省为当前 ref 名称，即 tag 推送触发时的 tag），其中 `/` 会替换为 `-`。Windows 产物静态链接运行库，可独立运行；Linux 产物静态链接 C++ 标准库；macOS 产物动态链接。

## Release 上传规则

- 设置 `release: true` 才上传构建产物，缺省仅构建不上传，便于日常测试；目标 Release 的 tag 取 `tag` 参数（缺省为当前 ref 名称，tag 推送触发时即该 tag）。
- Release 不存在时自动创建：标题取 `release-name`（缺省与 tag 同名），正文取 `release-body`（缺省自动生成）；`prerelease` / `draft` 参数控制对应标记。
- `extra-files` 可将额外文件（如 LICENSE、配置文件）随产物一起上传，每行一个，相对于 `base-dir`，不支持目录。
- 使用 `--clobber` 上传，重复执行会覆盖同名产物；多平台矩阵的各个任务向同一个 Release 上传各自平台的产物。
