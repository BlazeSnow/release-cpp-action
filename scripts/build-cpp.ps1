# 构建 Cpp 程序（Windows）
# 读取环境变量：
#   PROGRAM_NAME   程序名称（必填）
#   PROGRAM_VERSION  版本号（必填，进入产物文件名）
#   BASE_DIR      BASE 目录（默认 .）
#   CXX_STANDARD  C++ 标准（仅直接编译模式，编号或完整 -std 值，默认 17）
#   C_STANDARD    C 标准（仅直接编译模式，编号或完整 -std 值，缺省为编译器默认）
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
# C++ 标准：编号（如 17）或完整 -std 值（如 gnu++20），默认 17
$std = $env:CXX_STANDARD
if ([string]::IsNullOrWhiteSpace($std)) {
	$std = '17'
}
if ($std -notmatch '^(c\+\+|gnu\+\+)') {
	$std = "c++$std"
}
# C 标准：编号（如 11）或完整 -std 值（如 gnu11），缺省为编译器默认
$cStd = $env:C_STANDARD
if (-not [string]::IsNullOrWhiteSpace($cStd) -and $cStd -notmatch '^(c|gnu)') {
	$cStd = "c$cStd"
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
	# 直接编译模式：编译 BASE 目录顶层的 C/C++ 源文件（不递归）
	$sources = @(Get-ChildItem -LiteralPath $baseDir -File |
		Where-Object { $_.Extension -in '.c', '.cpp', '.cc', '.cxx' })
	if (-not $sources) {
		Fail "$baseDir 下既无 CMakeLists.txt 也无 C/C++ 源文件（*.c/*.cpp/*.cc/*.cxx）"
	}

	# 按语言分组
	$cSources = @($sources | Where-Object { $_.Extension -eq '.c' })
	$cxxSources = @($sources | Where-Object { $_.Extension -ne '.c' })

	$cStdFlags = @()
	if ($cStd) {
		$cStdFlags = @("-std=$cStd")
	}

	# C 编译器：GitHub 托管 Windows 运行器自带 MinGW
	$cCompiler = $null
	foreach ($candidate in 'gcc', 'cc') {
		if (Get-Command $candidate -ErrorAction SilentlyContinue) {
			$cCompiler = $candidate
			break
		}
	}

	if (-not $cxxSources) {
		# 纯 C：C 编译器直接编译链接
		if (-not $cCompiler) {
			Fail '未找到 C 编译器 gcc/cc（GitHub 托管 Windows 运行器自带 MinGW）'
		}
		# -static 静态链接运行库，产物免依赖可独立分发
		& $cCompiler @cStdFlags -O2 -static -o $output $cSources.FullName
		if ($LASTEXITCODE -ne 0) { Fail '编译失败' }
	}
	else {
		if (-not (Get-Command 'g++' -ErrorAction SilentlyContinue)) {
			Fail '未找到 C++ 编译器 g++（GitHub 托管 Windows 运行器自带 MinGW）'
		}
		$cObjects = @()
		if ($cSources) {
			# .c 需由 C 编译器单独编译成 .o（C++ 编译器会把 .c 当 C++ 编译），再与 C++ 源文件一并链接
			if (-not $cCompiler) {
				Fail '未找到 C 编译器 gcc/cc（GitHub 托管 Windows 运行器自带 MinGW）'
			}
			$objDir = Join-Path ([System.IO.Path]::GetTempPath()) ("release-cpp-action-" + [System.Guid]::NewGuid().ToString('N'))
			New-Item -ItemType Directory -Path $objDir | Out-Null
			foreach ($src in $cSources) {
				$obj = Join-Path $objDir ($src.BaseName + '.o')
				& $cCompiler @cStdFlags -O2 -c -o $obj $src.FullName
				if ($LASTEXITCODE -ne 0) { Fail "编译失败: $($src.Name)" }
				$cObjects += $obj
			}
		}
		# -static 静态链接运行库，产物免依赖可独立分发；"-std=$std" 必须带引号，否则 PowerShell 按字面量传递
		$linkSources = @($cxxSources.FullName) + $cObjects
		& g++ "-std=$std" -O2 -static -o $output $linkSources
		if ($LASTEXITCODE -ne 0) { Fail '编译失败' }
		if ($cObjects) {
			Remove-Item -LiteralPath $objDir -Recurse -Force
		}
	}
}

if ($env:GITHUB_OUTPUT) {
	# 输出统一使用正斜杠，便于下游（包括 Windows 上的 bash）直接使用
	Add-Content -Path $env:GITHUB_OUTPUT -Value "artifact-path=$($output -replace '\\', '/')" -Encoding utf8NoBOM
}
Write-Host "构建完成: $output"
