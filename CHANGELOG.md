# 更新日志

## v1.0-beta.1

1. 首个预发布版本
2. composite Action：输入 `name`（程序名称）与 `base-dir`（BASE 目录），构建 Cpp 程序并上传产物至 GitHub Release
3. 构建脚本：`scripts/build-cpp.sh`（Linux / bash）、`scripts/build-cpp-macos.sh`（macOS / zsh）与 `scripts/build-cpp.ps1`（Windows / PowerShell）
4. 支持两种构建模式：BASE 目录含 `CMakeLists.txt` 时走 CMake，否则直接编译目录下的 `*.cpp` / `*.cc` / `*.cxx`
5. 产物命名 `<name>-<version>-<os>-<arch>[.exe]`（版本号取 `tag` 输入，缺省为当前 ref 名称），输出到 `<base-dir>/dist/`，输出 `version` 与 `artifact-path`
6. Release 上传开关 `release` 与参数：`extra-files`、`release-body`、`release-name`、`prerelease`、`draft`、`tag`、`token`
7. 仓库发版流程：tag 与 `VERSION` 校验、GitHub Release 创建、正式版主版本标签跟随（`scripts/verify-tag-version.sh`、`scripts/update-major-tag.sh`、`tag.ps1`）
8. 多平台矩阵测试工作流 `test.yml`（linux/macOS/Windows 的 x64 与 arm64 × 两种构建模式）
