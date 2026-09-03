# DEVELOPMENT

## 架构

| 文件 | 说明 |
| --- | --- |
| `action.yml` | composite Action 入口：构建 + 上传 Release |
| `scripts/build-cpp.sh` | Linux 构建脚本（bash） |
| `scripts/build-cpp-macos.sh` | macOS 构建脚本（zsh） |
| `scripts/build-cpp.ps1` | Windows 构建脚本（PowerShell） |
| `scripts/upload-release.sh` | 上传产物至 GitHub Release（bash，各平台通用） |
| `.github/workflows/test.yml` | 多平台矩阵测试（本仓库自测） |
| `.github/workflows/release.yml` | 本仓库发版流程（tag 触发） |
| `scripts/verify-tag-version.sh` | 校验触发 tag 与 `VERSION` 一致 |
| `scripts/update-major-tag.sh` | 正式版强制更新主版本标签（`v1`） |
| `tag.ps1` | 本地读取 `VERSION` 创建并推送 tag |
| `test/`、`test/cmake/` | 直接编译与 CMake 两种模式的测试样例 |
| `test/verify-output.sh` | 测试用：运行产物并校验输出 |

## Action 流程

1. 构建步骤按 `runner.os` 分流：Linux 走 `build-cpp.sh`（bash），macOS 走 `build-cpp-macos.sh`（`shell: zsh {0}` 直接执行，脚本有可执行位；macOS 自带 bash 3.2 过老，故用默认 shell zsh，可用 `(N)` glob 限定符、递归 glob 等 zsh 特性），Windows 走 `build-cpp.ps1`；参数经环境变量 `PROGRAM_NAME`、`PROGRAM_VERSION`（取 `tag` 输入，缺省为当前 ref 名称，即 tag 推送触发时的 tag）、`BASE_DIR` 传入，避免 shell 注入。
2. 构建脚本自动检测平台与架构，产物命名 `<name>-<version>-<os>-<arch>[.exe]`（版本号中的 `/` 替换为 `-`，兼容 PR 触发时的 `<PR 号>/merge`），输出到 `<base-dir>/dist/`，并通过 `GITHUB_OUTPUT` 回写 `artifact-path`。
3. 上传步骤始终执行 `scripts/upload-release.sh`，由脚本内的 `RELEASE` 开关控制，仅显式 `true` 时上传。布尔开关不能写在步骤 `if` 上——composite 输入在表达式里是字符串，`'false'` 也为真。
4. 上传逻辑（读取 `TAG_NAME`、`EXTRA_FILES`、`RELEASE_BODY`、`RELEASE_NAME`、`PRERELEASE`、`DRAFT`）：Release 不存在则创建，随后 `gh release upload --clobber`。多平台矩阵会并发创建 Release，创建失败大概率是其他矩阵任务已建好，故容错跳过。

### CMake 模式

- 配置：`cmake -S <base-dir> -B <base-dir>/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=<base-dir>/build/bin`
- 要求 CMake 目标名与输入 `name` 一致；若项目自定义了输出目录或多配置生成器（如 Visual Studio）把产物放进子目录，脚本会递归查找兜底（排除 `CMakeFiles/`）。

### 直接编译模式

- 编译 `<base-dir>` 顶层（不递归）的 `*.cpp` / `*.cc` / `*.cxx`。
- 编译器：Linux/macOS 优先 `c++`，回退 `g++`；Windows 使用 MinGW `g++`（GitHub 托管运行器预装）。
- 编译参数：`-std=c++17 -O2`。
- 链接策略：Windows `-static`（产物免依赖）；Linux `-static-libstdc++ -static-libgcc`；macOS 动态链接（不支持静态 libstdc++）。

## 编码规范（GBK 与 UTF-8）

- 所有文本文件统一 **UTF-8 无 BOM**，唯一例外：`*.ps1` 使用 **UTF-8 带 BOM**。Windows PowerShell 5.1 在无 BOM 时按系统 ANSI（简体中文系统即 GBK / cp936）解码脚本，中文注释会乱码甚至解析失败；带 BOM 可同时兼容 5.1 与 PowerShell 7，与 `tag.ps1` 约定一致。
- `.gitattributes` 已固定换行符：`.sh` / `.yml` 为 LF，`.ps1` 为 CRLF。新增文件类型时注意补充规则。
- CI 上所有日志为 UTF-8，中文正常显示；在 GBK 代码页的 Windows 控制台本地运行 ps1 时，第三方工具输出的中文可能乱码，不影响 CI。
- 禁止以 GBK 编码保存任何文件。

## 本地测试

```bash
# 语法检查
bash -n scripts/*.sh test/verify-output.sh

# PowerShell 解析检查（本机为 GBK 代码页，可顺带验证 BOM 是否正确）
powershell.exe -NoProfile -Command "$t=$null; $e=$null; [System.Management.Automation.Language.Parser]::ParseFile('E:\release-cpp-action\scripts\build-cpp.ps1', [ref]$t, [ref]$e) | Out-Null; if ($e) { $e | ForEach-Object { $_.Message }; exit 1 } else { 'ps1 OK' }"

# 功能测试（build-cpp.sh 仅 Linux、build-cpp-macos.sh 仅 macOS，均无法在本地运行；
# Windows 本机用 ps1 验证，Git Bash 的 uname 为 MINGW64_NT-*，会被脚本明确拒绝）
# macOS 脚本仅做本地静态检查（如有 zsh）：zsh -n scripts/build-cpp-macos.sh
PROGRAM_NAME=hello-test PROGRAM_VERSION=v0.0.0-local BASE_DIR=test powershell.exe -NoProfile -File scripts/build-cpp.ps1
# CMake 模式（本机需安装 cmake）
PROGRAM_NAME=hello-test PROGRAM_VERSION=v0.0.0-local BASE_DIR=test/cmake powershell.exe -NoProfile -File scripts/build-cpp.ps1

# 运行产物
./test/dist/hello-test-v0.0.0-local-windows-x64.exe
```

CI 测试：`test.yml` 在 push（`dev` / `main`）、PR、手动触发时，以 6 个运行器（linux/macOS/Windows 的 x64 与 arm64）× 2 构建模式共 12 个矩阵任务运行本 Action，并运行产物校验输出。测试不在 tag push 时触发，因此不会向 Release 误传测试产物。

## 发版流程

1. 更新 `VERSION`（如 `v1.0.0`）与 `CHANGELOG.md`
2. 提交后运行 `./tag.ps1`，确认后自动创建并推送 tag
3. `release.yml` 自动执行：校验 tag 与 `VERSION` 一致 → 创建 Release（body 指向 CHANGELOG.md）→ 正式版（tag 不含 `-`）更新主版本标签（`v1.0.0` → `v1`）；预发布版本跳过主版本标签更新
