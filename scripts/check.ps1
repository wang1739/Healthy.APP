$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
    git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Git whitespace check failed.' }

    $sensitiveFiles = git ls-files | Select-String -Pattern '(^|/)(\.env|key\.properties|.*\.(jks|keystore))$'
    if ($sensitiveFiles) { throw "Sensitive files are tracked:`n$sensitiveFiles" }

    foreach ($requiredFile in 'index.html', 'nutrition.html', 'api.js') {
        if (-not (Test-Path -LiteralPath $requiredFile)) { throw "Missing required file: $requiredFile" }
    }

    Push-Location 'backend'
    try {
        & .\mvnw.cmd test
        if ($LASTEXITCODE -ne 0) { throw 'Backend tests failed.' }
    }
    finally {
        Pop-Location
    }

    Write-Host 'All project checks passed.' -ForegroundColor Green
}
finally {
    Pop-Location
}
