# release-cpp-action

构建 C/C++ 程序并上传构建产物至 GitHub Release。

> **注意**：项目目前处于测试阶段，尚未发布 v1 正式版，`@v1` 引用暂不可用，请先使用 `@main`。

## 用法

在自己仓库的 workflow 中以多平台矩阵调用：

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
        os: [ubuntu-latest, ubuntu-24.04-arm, macos-latest, macos-26-intel, windows-latest, windows-11-arm]
    runs-on: ${{ matrix.os }}
    steps:
    - uses: actions/checkout@v7
    - uses: BlazeSnow/release-cpp-action@main
      with:
        name: myapp
        base-dir: src
        release: true
        prerelease: ${{ contains(github.ref_name, '-') }}
```

产物命名 `<name>-<版本>-<os>-<arch>[.exe]`（如 `myapp-v1.0.0-windows-x64.exe`），版本号取 `tag` 参数，缺省为当前 ref 名称。开启 `release` 后产物上传至该 tag 的 Release，不存在则自动创建。

## 输入参数

| 参数 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `name` | 是 | - | 程序名称，用作编译目标名与产物文件名前缀 |
| `base-dir` | 否 | `.` | BASE 目录，即 Cpp 源码所在目录 |
| `cxx-standard` | 否 | `17` | C++ 标准，仅直接编译模式：编号（`11`/`14`/`17`/`20`/`23`/`26`）或完整 `-std` 值（如 `gnu++20`）；CMake 模式由 `CMakeLists.txt` 决定 |
| `c-standard` | 否 | 编译器默认 | C 标准，仅直接编译模式：编号（`99`/`11`/`17`/`23`）或完整 `-std` 值（如 `gnu11`）；CMake 模式由 `CMakeLists.txt` 决定 |
| `release` | 否 | `false` | 是否上传构建产物至 GitHub Release |
| `extra-files` | 否 | - | 额外上传的文件，每行一个（相对于 `base-dir`） |
| `release-body` | 否 | 自动生成 | Release 正文（仅在自动创建 Release 时使用） |
| `release-name` | 否 | tag | 自定义 Release 标题 |
| `prerelease` | 否 | `false` | 将 Release 标记为预发布版本 |
| `draft` | 否 | `false` | 将 Release 存为草稿，不直接发布 |
| `tag` | 否 | 当前 ref 名称 | 目标 Release 的 tag |
| `token` | 否 | `github.token` | GitHub Token（用于创建/上传 Release） |

输出：`artifact-path`（构建产物路径）、`version`（版本号）。

## 构建规则

- `base-dir` 下有 `CMakeLists.txt` 走 CMake（Release 模式，目标名需与 `name` 一致）；否则直接编译该目录下的 `*.c` / `*.cpp` / `*.cc` / `*.cxx`（`-O2`，不递归；C++ 标准由 `cxx-standard` 指定，默认 C++17，C 标准由 `c-standard` 指定，缺省为编译器默认；同时含 C++ 与 C 源文件时，`.c` 由 C 编译器单独编译后与 C++ 一并链接）
- 产物输出到 `<base-dir>/dist/`；Windows 静态链接可独立运行，Linux 静态链接 C++ 运行库，macOS 动态链接

## License

[MIT](LICENSE) © [BlazeSnow](https://github.com/BlazeSnow)
