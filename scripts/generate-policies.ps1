#!/usr/bin/env pwsh
# ============================================================================
# scripts/generate-policies.ps1 - Genera docs/policies/{dev,prod}/*.json
# ============================================================================
# Transforma los 4 archivos JSON originales en docs/policies/ en 8 archivos:
# docs/policies/{dev,prod}/<nombre>.json
# con ${environment} interpolado en los ARN wildcards pertinentes.
#
# Algoritmo: encuentra TODAS las matches sobre el contenido ORIGINAL, las
# resuelve por offset (mas largo gana en caso de solapamiento), y las aplica
# en orden descendente. Esto evita el problema de "cascada" donde una
# transformacion aplica ${environment} y otra regla matchea la salida.
# ============================================================================
param(
    [string]$SourceDir = "$PSScriptRoot/../docs/policies",
    [string]$TargetRoot = "$PSScriptRoot/../docs/policies"
)

$ErrorActionPreference = "Stop"

# --- Transformaciones (orden solo afecta el orden de procesamiento en caso de
#     empate de longitud; la deduplicacion posterior es por offset y longitud) ---
$transforms = @(
    @{ Pattern = 'spark-match-backend-\*-exec-\*';       Replace = 'spark-match-backend-*-exec-${environment}' }
    @{ Pattern = 'spark-match-backend-deploy-\*';          Replace = 'spark-match-backend-deploy-${environment}' }
    @{ Pattern = 'spark-match-backend-\*:\*';              Replace = 'spark-match-backend-*-${environment}:*' }
    @{ Pattern = 'spark-match-backend-\*/\*';              Replace = 'spark-match-backend-*-${environment}/*' }
    @{ Pattern = 'spark-match-backend-\*';                 Replace = 'spark-match-backend-*-${environment}' }
    @{ Pattern = 'spark-match-node-shared-\*';             Replace = 'spark-match-node-shared-*-${environment}' }
    @{ Pattern = 'spark-match-node-runtime-\*';            Replace = 'spark-match-node-runtime-*-${environment}' }
    @{ Pattern = 'spark-match-python-shared-\*';           Replace = 'spark-match-python-shared-*-${environment}' }
    @{ Pattern = 'spark-match-python-runtime-\*';          Replace = 'spark-match-python-runtime-*-${environment}' }
    @{ Pattern = 'spark-match-agentcore-exec-\*';          Replace = 'spark-match-agentcore-exec-${environment}' }
    @{ Pattern = 'spark-match-agentcore-runtime-\*';       Replace = 'spark-match-agentcore-runtime-${environment}' }
    @{ Pattern = 'spark-match-lambda-runtime-\*';          Replace = 'spark-match-lambda-runtime-${environment}' }
    @{ Pattern = 'spark-match-sam-artifacts-\*';           Replace = 'spark-match-sam-artifacts-${environment}' }
    @{ Pattern = 'spark-match-rag-documents-\*';           Replace = 'spark-match-rag-documents-${environment}' }
    @{ Pattern = 'spark-match-events-\*';                  Replace = 'spark-match-events-${environment}' }
    @{ Pattern = 'spark-match-agent-\*';                   Replace = 'spark-match-agent-*-${environment}' }
    @{ Pattern = 'spark-match-aurora-\*';                  Replace = 'spark-match-aurora-${environment}-*' }
    @{ Pattern = 'spark-match-tfstate-prod';               Replace = 'spark-match-tfstate-${environment}' }
    @{ Pattern = '/aws/lambda/spark-match-backend-\*';     Replace = '/aws/lambda/spark-match-backend-*-${environment}' }
    @{ Pattern = '/aws/spark-match/backend/\*';            Replace = '/aws/spark-match/backend/${environment}/*' }
    @{ Pattern = '/aws/spark-match/agent/\*';              Replace = '/aws/spark-match/agent/${environment}/*' }
    @{ Pattern = '/aws/bedrock-agentcore/\*';              Replace = '/aws/bedrock-agentcore/${environment}/*' }
    @{ Pattern = 'secret:spark-match/agent-user-\*';       Replace = 'secret:spark-match/agent-user-*-${environment}' }
    @{ Pattern = 'secret:spark-match/agent-\*';            Replace = 'secret:spark-match/agent-*-${environment}' }
    @{ Pattern = 'secret:spark-match/backend-\*';          Replace = 'secret:spark-match/backend-*-${environment}' }
)

# --- KMS Condition (SEC-03): agregar Environment a StringEquals ---
# Original: 10 espacios de indent antes de la key.
# Resultado: misma indentacion (10 espacios) en la nueva key.
$kmsConditionBefore = '"aws:ResourceTag/Project": "spark-match"'
$kmsConditionAfter  = ('"aws:ResourceTag/Project": "spark-match",' + [Environment]::NewLine + '          "aws:ResourceTag/Environment": "${environment}"')

function Apply-AllReplacements {
    param(
        [string]$Content,
        [array]$Transforms
    )

    # Encontrar todas las matches en el contenido ORIGINAL
    $allReplacements = New-Object System.Collections.Generic.List[object]
    foreach ($t in $Transforms) {
        $regex = [regex]$t.Pattern
        $matches = $regex.Matches($Content)
        foreach ($m in $matches) {
            $allReplacements.Add([pscustomobject]@{
                Start  = $m.Index
                Length = $m.Length
                Text   = $t.Replace
            })
        }
    }

    # Ordenar por Start, luego por Length DESC (mas largo gana en empate)
    $sorted = $allReplacements | Sort-Object Start, @{Expression={-$_.Length}}

    # Filtrar overlaps: si dos matches se solapan, descartamos el mas corto
    $filtered = New-Object System.Collections.Generic.List[object]
    $lastEnd = -1
    foreach ($r in $sorted) {
        $rEnd = $r.Start + $r.Length
        if ($r.Start -ge $lastEnd) {
            $filtered.Add($r)
            $lastEnd = $rEnd
        }
    }

    # Aplicar en orden DESCENDENTE para no afectar offsets
    $applied = $filtered | Sort-Object Start -Descending
    $result = $Content
    foreach ($r in $applied) {
        $result = $result.Remove($r.Start, $r.Length).Insert($r.Start, $r.Text)
    }

    return $result
}

function Apply-KMS-Condition {
    param([string]$Content)
    return $Content.Replace($kmsConditionBefore, $kmsConditionAfter)
}

# --- Generar docs/policies/{dev,prod}/ ---
$policies = @(
    "spark-match-sam-deploy.json"
    "spark-match-bedrock-agentcore-deploy.json"
    "spark-match-lambda-runtime.json"
    "spark-match-agentcore-runtime.json"
)

foreach ($env in @("dev", "prod")) {
    $targetDir = Join-Path $TargetRoot $env
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    foreach ($policy in $policies) {
        $sourcePath = Join-Path $SourceDir $policy
        $targetPath = Join-Path $targetDir $policy

        if (-not (Test-Path $sourcePath)) {
            Write-Error "Source no encontrado: $sourcePath"
            exit 1
        }

        $original = Get-Content -Path $sourcePath -Raw -Encoding UTF8
        $transformed = Apply-AllReplacements -Content $original -Transforms $transforms
        $transformed = Apply-KMS-Condition -Content $transformed
        Set-Content -Path $targetPath -Value $transformed -Encoding UTF8 -NoNewline

        Write-Host "  [ok] $env/$policy ($((Get-Content $targetPath -Raw).Length) bytes)"
    }
}

# --- Validar que el JSON es valido despues de las transformaciones ---
Write-Host ""
Write-Host "Validando JSON..."
$allValid = $true
foreach ($env in @("dev", "prod")) {
    foreach ($policy in $policies) {
        $path = Join-Path (Join-Path $TargetRoot $env) $policy
        try {
            $json = Get-Content -Path $path -Raw | ConvertFrom-Json
            $stmtCount = ($json.Statement | Measure-Object).Count
            Write-Host "  [valid] $env/$policy ($stmtCount statements)"
        }
        catch {
            Write-Host "  [FAIL] $env/$policy - $($_.Exception.Message)"
            $allValid = $false
        }
    }
}

if (-not $allValid) {
    Write-Host ""
    Write-Error "JSON invalido en uno o mas archivos. Abortando."
    exit 1
}

# --- Sanity checks via lectura directa (sin Select-String, que tiene problemas
#     con el escape de `$` en `-SimpleMatch`) ---
Write-Host ""
Write-Host "Sanity checks (SEC-02 / SEC-03):"

$devSamPath = Join-Path (Join-Path $TargetRoot 'dev') 'spark-match-sam-deploy.json'
$prodSamPath = Join-Path (Join-Path $TargetRoot 'prod') 'spark-match-sam-deploy.json'
$devSamContent = Get-Content -Path $devSamPath -Raw
$prodSamContent = Get-Content -Path $prodSamPath -Raw

$checks = @(
    @{ Name = 'SEC-02 dev tfstate parametrizado'; Pass = $devSamContent.Contains('spark-match-tfstate-${environment}') },
    @{ Name = 'SEC-02 prod sin tfstate-prod hardcoded'; Pass = -not $prodSamContent.Contains('spark-match-tfstate-prod"') },
    @{ Name = 'SEC-03 dev KMS Environment tag'; Pass = $devSamContent.Contains('aws:ResourceTag/Environment": "${environment}"') },
    @{ Name = 'SEC-03 prod KMS Environment tag'; Pass = $prodSamContent.Contains('aws:ResourceTag/Environment": "${environment}"') }
)

foreach ($c in $checks) {
    $tag = if ($c.Pass) { '[ok] ' } else { '[FAIL] ' }
    Write-Host "  $tag$($c.Name)"
    if (-not $c.Pass) { $allValid = $false }
}

if (-not $allValid) {
    Write-Host ""
    Write-Error "Sanity checks fallaron. Abortando."
    exit 1
}

Write-Host ""
Write-Host "[OK] 8 policies generadas y validadas en docs/policies/{dev,prod}/"
