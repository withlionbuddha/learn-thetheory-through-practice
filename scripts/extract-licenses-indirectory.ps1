# scripts\extract-licenses.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 1) 스크립트 및 프로젝트 루트 경로 설정
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir   = Split-Path -Parent $scriptDir  # 프로젝트 루트

# 2) requirements.txt 읽어 specs 리스트 생성
$reqFile = Join-Path $rootDir 'requirements.txt'
if (-not (Test-Path $reqFile)) {
    Write-Error "requirements.txt not found at $reqFile"
    exit 1
}
$specs = Get-Content $reqFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') }

Write-Host "--- Extracting license files from installed package directories ---"
# 3) 가상환경 설치 디렉터리 경로
$venv = $env:VIRTUAL_ENV
if (-not $venv) {
    Write-Warning 'VIRTUAL_ENV not set; skipping directory-based extraction.'
    Write-Host 'All done!'
    exit 0
}
$sitePkgs = Join-Path $venv 'Lib\site-packages'

# 4) specs마다 디렉터리 탐색 및 LICENSE 추출
foreach ($spec in $specs) {
    if ($spec -match '^([^=\s]+)==([^=\s]+)') {
        $name, $ver = $matches[1], $matches[2]
    } elseif ($spec -match '^([^=\s]+)>=(\d+(\.\d+){0,2})$') {
        $name, $ver = $matches[1], $matches[2]
    } else {
        Write-Warning "Skipping unsupported spec format: $spec"
        continue
    }
    $prefix = ($name -replace '_','-') + "-$ver"
    $dirs = Get-ChildItem -Path $sitePkgs -Directory |
            Where-Object { $_.Name -like "$prefix*" -or $_.Name -like "$name*" }
    if (-not $dirs) {
        Write-Warning "Package directory not found for $spec"
        continue
    }

     # 모든 LICENSE/COPYING 파일을 한 번에 수집
    $licenseFiles = foreach ($d in $dirs) {
        Get-ChildItem -Path $d.FullName -Include 'LICENSE*','COPYING*' -File -Recurse -ErrorAction SilentlyContinue
    }

    # 라이선스 파일이 하나도 없으면 폴더 생성 없이 건너뜀
    if ($licenseFiles.Count -eq 0) {
        Write-Warning "No license files found for package $name"
        continue
    }
    
     # 라이선스 파일이 있을 때만 출력 디렉터리 생성
    $outDir = Join-Path $rootDir 'THIRD-PARTY-LICENSES' |
              Join-Path -ChildPath $name
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

                # 파일 복사: 하위 폴더 구조 유지하며 extracted 폴더에 LICENSE 배치
    foreach ($file in $licenseFiles) {
        # 원본 디렉터리($dirs) 중 해당 파일이 속한 루트 찾기
        $parentDir = $dirs | Where-Object { $file.FullName.StartsWith($_.FullName) } | Select-Object -First 1
        # 파일의 상대 경로 (subfolder path)
        $relPath = $file.FullName.Substring($parentDir.FullName.Length).TrimStart('\')
        $subDir = Split-Path $relPath -Parent
        # 대상 하위 폴더 생성
        $targetDir = if ($subDir) { Join-Path $outDir $subDir } else { $outDir }
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item -Path $file.FullName -Destination (Join-Path $targetDir $file.Name) -Force
        Write-Host "→ $($name): Extracted $($relPath)"
    }
}

Write-Host 'All done!'
