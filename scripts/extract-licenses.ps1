# scripts\extract-licenses.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 1) 임시 작업 디렉터리 생성
$tempPath = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempPath | Out-Null

# 2) requirements.txt 경로 설정 및 내용 읽기
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir   # 프로젝트 루트 경로
$reqFile = Join-Path $rootDir 'requirements.txt'
if (-not (Test-Path $reqFile)) {
    Write-Error "requirements.txt not found at $reqFile"
    exit 1
}
# 주석과 빈 줄 제외하고 고유한 spec 리스트 생성
$specs = Get-Content $reqFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Select-Object -Unique
if ($specs.Count -eq 0) {
    Write-Warning 'No library specifications found in requirements.txt'
    exit 0
}

# 3) 각 spec에 대해 다운로드, 추출, LICENSE 복사
foreach ($spec in $specs) {
    # spec에서 패키지 이름 추출 (==, >=, <=, ~= 기준)
    $name = ($spec -split '[<>=~]+' )[0].Trim()

    Write-Host "Downloading $spec ..."
    # 이전 다운로드 파일 제거
    Get-ChildItem -Path $tempPath -File | Remove-Item -Force
    pip download "$spec" --no-deps -d $tempPath

    # 아카이브 찾기 (name-*)
    $archive = Get-ChildItem -Path $tempPath -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like "$name-*" } |
               Sort-Object -Property LastWriteTime -Descending |
               Select-Object -First 1
    if (-not $archive) {
        Write-Warning "Archive for $spec not found, skipping."
        continue
    }

    # dest 디렉토리 결정 및 생성
    $archiveBase = $archive.BaseName
    $destRoot = Join-Path $rootDir 'THIRD-PARTY-LICENSES'
    $dest = Join-Path $destRoot $archiveBase
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    Write-Host "Extracting $($archive.Name) ..."
    # 확장자에 따라 압축 해제
    switch ($archive.Extension.ToLower()) {
        '.zip' { Expand-Archive -LiteralPath $archive.FullName -DestinationPath $tempPath -Force }
        '.whl' {
            $zipTmp = Join-Path $tempPath ($archiveBase + ".zip")
            Copy-Item -Path $archive.FullName -Destination $zipTmp -Force
            Expand-Archive -LiteralPath $zipTmp -DestinationPath $tempPath -Force
            Remove-Item -Path $zipTmp -Force
        }
        default { tar -xzf $archive.FullName -C $tempPath }
    }

    # LICENSE 또는 COPYING 파일 검색 및 복사
    $licenseFile = Get-ChildItem -Path $tempPath -Include 'LICENSE*', 'COPYING*' -File -Recurse |
                   Select-Object -First 1
    if ($licenseFile) {
        Copy-Item -Path $licenseFile.FullName -Destination (Join-Path $dest 'LICENSE') -Force
        Write-Host "→ ${archiveBase}: LICENSE extracted to $dest\LICENSE"

    } else {
        Write-Warning "LICENSE file not found in $archiveBase"
    }
}

# 4) 임시 작업 디렉터리 삭제
if (Test-Path $tempPath) { Remove-Item -Recurse -Force $tempPath }

Write-Host 'All done!'
