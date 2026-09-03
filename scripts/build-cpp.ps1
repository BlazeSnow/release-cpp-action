# 构建 Cpp 程序（Windows）
# 读取环境变量：
#   PROGRAM_NAME   程序名称（必填）
#   PROGRAM_VERSION  版本号（必填，进入产物文件名）
#   BASE_DIR      BASE 目录（默认 .）
# 产物输出到 <BASE_DIR>/dist/<name>-<version>-windows-<arch>.exe
$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
	Write-Output "::error::$message"
	exit 1
}

$name = $env:PROGRAM_NAME
if ([string]::IsNullOrWhiteSpace($name)) {
	Fail '缺少环境变量 PROGRAM_NAME'
}
$version = $env:PROGRAM_VERSION
if ([string]::IsNullOrWhiteSpace($version)) {
	Fail '缺少环境变量 PROGRAM_VERSION'
}
# ref 名可能含 /（如 PR 触发时的 <PR 号>/merge），替换为 - 保证产物名合法
$version = $version.Replace('/', '-')
$baseDir = $env:BASE_DIR
if ([string]::IsNullOrWhiteSpace($baseDir)) {
	$baseDir = '.'
}

if (-not (Test-Path -LiteralPath $baseDir -PathType Container)) {
	Fail "BASE 目录不存在: $baseDir"
}

$os = 'windows'
$arch = $env:PROCESSOR_ARCHITECTURE
switch ($arch) {
	'AMD64' { $arch = 'x64' }
	'ARM64' { $arch = 'arm64' }
	default { $arch = $arch.ToLowerInvariant() }
}

$distDir = Join-Path $baseDir 'dist'
$output = Join-Path $distDir "$name-$version-$os-$arch.exe"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$cmakeLists = Join-Path $baseDir 'CMakeLists.txt'
if (Test-Path -LiteralPath $cmakeLists -PathType Leaf) {
	# CMake 模式：要求 CMake 目标名与程序名称一致
	$buildDir = Join-Path $baseDir 'build'
	$binDir = Join-Path $buildDir 'bin'
	cmake -S $baseDir -B $buildDir -DCMAKE_BUILD_TYPE=Release -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$binDir"
	if ($LASTEXITCODE -ne 0) { Fail 'CMake 配置失败' }
	cmake --build $buildDir --config Release --parallel
	if ($LASTEXITCODE -ne 0) { Fail 'CMake 构建失败' }

	$built = Join-Path $binDir "$name.exe"
	if (-not (Test-Path -LiteralPath $built -PathType Leaf)) {
		# 兜底：项目自定义输出目录或多配置生成器时递归查找
		$candidates = Get-ChildItem -Path $buildDir -Recurse -Filter "$name.exe" -File |
			Where-Object { $_.FullName -notmatch '\\CMakeFiles\\' }
		if (-not $candidates) {
			Fail "CMake 构建完成但未找到产物: $name.exe"
		}
		$built = $candidates[0].FullName
	}
	Move-Item -LiteralPath $built -Destination $output -Force
}
else {
	# 直接编译模式：编译 BASE 目录顶层的 Cpp 源文件（不递归）
	$sources = Get-ChildItem -LiteralPath $baseDir -File |
		Where-Object { $_.Extension -in '.cpp', '.cc', '.cxx' }
	if (-not $sources) {
		Fail "$baseDir 下既无 CMakeLists.txt 也无 Cpp 源文件（*.cpp/*.cc/*.cxx）"
	}

	if (-not (Get-Command 'g++' -ErrorAction SilentlyContinue)) {
		Fail '未找到 C++ 编译器 g++（GitHub 托管 Windows 运行器自带 MinGW）'
	}

	# -static 静态链接运行库，产物免依赖可独立分发
	& g++ -std=c++17 -O2 -static -o $output $sources.FullName
	if ($LASTEXITCODE -ne 0) { Fail '编译失败' }
}

if ($env:GITHUB_OUTPUT) {
	# 输出统一使用正斜杠，便于下游（包括 Windows 上的 bash）直接使用
	Add-Content -Path $env:GITHUB_OUTPUT -Value "artifact-path=$($output -replace '\\', '/')" -Encoding utf8NoBOM
}
Write-Host "构建完成: $output"
