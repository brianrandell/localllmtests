<#
.SYNOPSIS
    Master GGUF Model Download Script for Brian's AI Lab
    
.DESCRIPTION
    Downloads all benchmark models organized by VRAM profile and use case.
    Uses hf CLI for reliable downloads (handles split files and XET storage).
    
.NOTES
    Date: 2026-02-28 (v3 - Unified hf CLI approach for reliability)
    Total Download Size: ~750 GB (all models)
    
    Prerequisites:
    - pip install huggingface_hub hf_transfer
    - hf auth login
    - Set $env:HF_HUB_ENABLE_HF_TRANSFER = "1" for faster downloads
#>

param(
    [string]$ModelDir = "E:\llama-tests\gguf",
    [switch]$DryRun,
    [ValidateSet("All", "11GB", "24GB", "32GB", "96GB")]
    [string]$Category = "All",
    [switch]$SkipPrereqCheck
)

# Ensure directory exists
if (-not (Test-Path $ModelDir)) {
    New-Item -ItemType Directory -Path $ModelDir -Force | Out-Null
}

# Enable fast transfers
$env:HF_HUB_ENABLE_HF_TRANSFER = "1"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  AI Lab Model Download Script v3" -ForegroundColor Cyan
Write-Host "  Updated: 2026-02-28" -ForegroundColor Cyan
Write-Host "  Target: $ModelDir" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
if (-not $SkipPrereqCheck) {
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow
    
    if (-not (Get-Command hf -ErrorAction SilentlyContinue)) {
        Write-Host "  [MISSING] hf CLI" -ForegroundColor Red
        Write-Host "           Install: pip install huggingface_hub hf_transfer" -ForegroundColor Yellow
        Write-Host "           Login:   hf auth login" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "  [OK] hf CLI" -ForegroundColor Green
    }
    Write-Host ""
}

# Helper function for downloads
function Download-Model {
    param(
        [string]$Repo,
        [string]$Include,
        [string]$OutputDir,
        [string]$Description
    )
    
    Write-Host "  Downloading: $Description" -ForegroundColor Yellow
    if ($DryRun) {
        Write-Host "    [DRY RUN] hf download $Repo --include `"$Include`" --local-dir `"$OutputDir`"" -ForegroundColor DarkGray
    } else {
        hf download $Repo --include $Include --local-dir $OutputDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    [FAILED] $Description" -ForegroundColor Red
        } else {
            Write-Host "    [OK]" -ForegroundColor Green
        }
    }
}

#=============================================================================
# 11GB PROFILE (GTX 1080 Ti, RTX 2080 Ti)
#=============================================================================
if ($Category -eq "All" -or $Category -eq "11GB") {
    Write-Host "`n[11GB PROFILE - Legacy Cards]" -ForegroundColor Green
    
    Download-Model -Repo "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF" `
        -Include "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "Llama 3.1 8B Q4 (~4.9GB)"

    Download-Model -Repo "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF" `
        -Include "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 2.5 Coder 7B Q4 (~4.7GB)"
}

#=============================================================================
# 24GB PROFILE (RTX 3090, 4090, 5090)
#=============================================================================
if ($Category -eq "All" -or $Category -eq "24GB") {
    Write-Host "`n[24GB PROFILE - Consumer Flagship]" -ForegroundColor Green

    Download-Model -Repo "bartowski/Ministral-8B-Instruct-2410-GGUF" `
        -Include "Ministral-8B-Instruct-2410-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "Ministral 8B Q4 (~4.9GB)"

    Download-Model -Repo "bartowski/phi-4-GGUF" `
        -Include "phi-4-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "Phi-4 14B Q4 (~8.4GB)"

    Download-Model -Repo "bartowski/Qwen2.5-Coder-32B-Instruct-GGUF" `
        -Include "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 2.5 Coder 32B Q4 (~18.5GB)"

    Download-Model -Repo "unsloth/Nemotron-3-Nano-30B-A3B-GGUF" `
        -Include "Nemotron-3-Nano-30B-A3B-UD-Q4_K_XL.gguf" `
        -OutputDir $ModelDir `
        -Description "Nemotron-3-Nano 30B-A3B Q4 (~18GB) [MoE]"

    # Qwen 3.5 35B-A3B + vision projector
    Download-Model -Repo "unsloth/Qwen3.5-35B-A3B-GGUF" `
        -Include "Qwen3.5-35B-A3B-UD-Q4_K_XL.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 3.5 35B-A3B Q4 (~20GB) [MoE] ★NEW"

    Download-Model -Repo "unsloth/Qwen3.5-35B-A3B-GGUF" `
        -Include "mmproj-BF16.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 3.5 35B Vision Projector (~900MB)"
    # Rename vision projector to avoid conflicts
    $mmproj35 = Join-Path $ModelDir "mmproj-BF16.gguf"
    $mmproj35New = Join-Path $ModelDir "Qwen3.5-35B-A3B-mmproj-BF16.gguf"
    if ((Test-Path $mmproj35) -and -not (Test-Path $mmproj35New)) {
        Rename-Item $mmproj35 $mmproj35New
    }
}

#=============================================================================
# 32GB PROFILE (RTX 5090)
#=============================================================================
if ($Category -eq "All" -or $Category -eq "32GB") {
    Write-Host "`n[32GB PROFILE - RTX 5090]" -ForegroundColor Green

    Download-Model -Repo "bartowski/Qwen2.5-Coder-32B-Instruct-GGUF" `
        -Include "Qwen2.5-Coder-32B-Instruct-Q6_K.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 2.5 Coder 32B Q6 (~25GB)"

    Download-Model -Repo "unsloth/Qwen3.5-27B-GGUF" `
        -Include "Qwen3.5-27B-Q6_K.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 3.5 27B Dense Q6 (~22GB) ★NEW"
}

#=============================================================================
# 96GB PROFILE (RTX PRO 6000 Blackwell)
#=============================================================================
if ($Category -eq "All" -or $Category -eq "96GB") {
    Write-Host "`n[96GB PROFILE - RTX PRO 6000 Blackwell]" -ForegroundColor Green

    # Single-file models
    Download-Model -Repo "bartowski/DeepSeek-R1-Distill-Llama-70B-GGUF" `
        -Include "DeepSeek-R1-Distill-Llama-70B-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "DeepSeek-R1 70B Q4 (~40GB)"

    # Split models - download all parts
    Write-Host "`n  -- Split Models (multi-part) --" -ForegroundColor Magenta

    Download-Model -Repo "bartowski/Qwen2.5-72B-Instruct-GGUF" `
        -Include "Qwen2.5-72B-Instruct-Q4_K_M.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 2.5 72B Q4 (~44GB)"

    Download-Model -Repo "bartowski/Qwen2.5-72B-Instruct-GGUF" `
        -Include "Qwen2.5-72B-Instruct-Q8_0/*" `
        -OutputDir $ModelDir `
        -Description "Qwen 2.5 72B Q8 (~72GB) [Split]"

    Download-Model -Repo "bartowski/Meta-Llama-3.1-70B-Instruct-GGUF" `
        -Include "Meta-Llama-3.1-70B-Instruct-Q6_K/*" `
        -OutputDir $ModelDir `
        -Description "Llama 3.1 70B Q6 (~54GB) [Split]"

    Download-Model -Repo "bartowski/Meta-Llama-3.1-70B-Instruct-GGUF" `
        -Include "Meta-Llama-3.1-70B-Instruct-Q8_0/*" `
        -OutputDir $ModelDir `
        -Description "Llama 3.1 70B Q8 (~70GB) [Split]"

    Download-Model -Repo "bartowski/c4ai-command-r-plus-08-2024-GGUF" `
        -Include "c4ai-command-r-plus-08-2024-Q4_K_M/*" `
        -OutputDir $ModelDir `
        -Description "Command-R+ 104B Q4 (~58GB) [Split]"

    Download-Model -Repo "bartowski/c4ai-command-r-plus-08-2024-GGUF" `
        -Include "c4ai-command-r-plus-08-2024-Q6_K/*" `
        -OutputDir $ModelDir `
        -Description "Command-R+ 104B Q6 (~79GB) [Split]"

    # Qwen 3.5 122B-A10B (split)
    Download-Model -Repo "unsloth/Qwen3.5-122B-A10B-GGUF" `
        -Include "Q4_K_M/*" `
        -OutputDir "$ModelDir\Qwen3.5-122B" `
        -Description "Qwen 3.5 122B-A10B Q4 (~70GB) [MoE Split] ★NEW"

    Download-Model -Repo "unsloth/Qwen3.5-122B-A10B-GGUF" `
        -Include "mmproj-BF16.gguf" `
        -OutputDir $ModelDir `
        -Description "Qwen 3.5 122B Vision Projector (~900MB)"
    # Rename vision projector
    $mmproj122 = Join-Path $ModelDir "mmproj-BF16.gguf"
    $mmproj122New = Join-Path $ModelDir "Qwen3.5-122B-A10B-mmproj-BF16.gguf"
    if ((Test-Path $mmproj122) -and -not (Test-Path $mmproj122New)) {
        Rename-Item $mmproj122 $mmproj122New
    }

    # GPT-OSS
    Download-Model -Repo "ggml-org/gpt-oss-120b-GGUF" `
        -Include "gpt-oss-120b-mxfp4*" `
        -OutputDir "$ModelDir\gpt-oss-120b" `
        -Description "GPT-OSS 120B MXFP4 (~59GB) [MoE Split]"

    Download-Model -Repo "ggml-org/gpt-oss-20b-GGUF" `
        -Include "gpt-oss-20b-mxfp4.gguf" `
        -OutputDir $ModelDir `
        -Description "GPT-OSS 20B MXFP4 (~12GB)"
}

#=============================================================================
# SUMMARY
#=============================================================================
Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  Download Complete!" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Model Directory: $ModelDir" -ForegroundColor White
Write-Host ""
Write-Host "Verify downloads:" -ForegroundColor Yellow
Write-Host '  Get-ChildItem "$ModelDir" -Recurse -Filter "*.gguf" | Measure-Object -Property Length -Sum | Select-Object @{N="TotalGB";E={[math]::Round($_.Sum/1GB,1)}}' -ForegroundColor Gray
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No files were downloaded]" -ForegroundColor Red
}