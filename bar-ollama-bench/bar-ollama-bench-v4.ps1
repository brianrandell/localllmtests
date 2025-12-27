param(
  [Parameter(Mandatory=$true)]
  [string]$Mode,

  # JSON config file with models and prompts
  [Parameter(Mandatory=$true)]
  [string]$ConfigFile,

  [string]$LogDir = ".\logs",

  # Resume in-place in this folder (e.g. .\logs\5090-pcie-headless)
  [string]$RunRoot = "",

  [int]$SmiIntervalSeconds = -1,  # -1 means use config file value
  [int]$RepeatCount = -1,         # -1 means use config file value
  [switch]$Resume,
  
  # Quick test mode: first model only, 1 repeat
  [switch]$QuickTest,
  
  # Override models (comma-separated, e.g. "llama3.2,ministral-3")
  [string]$ModelOverride = "",
  
  # Fresh mode: call "ollama stop" before each repeat to get clean-load performance
  # Without this flag, runs in "steady state" mode (model stays loaded)
  [switch]$FreshMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------
# Load and validate config
# ---------------------------
$configPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigFile)
if (-not (Test-Path $configPath)) {
  throw "Config file not found: $configPath"
}

Write-Host "Loading config from: $configPath" -ForegroundColor Cyan
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

# Validate required sections
if (-not $config.models -or $config.models.Count -eq 0) {
  throw "Config file must contain a non-empty 'models' array"
}
if (-not $config.prompts -or $config.prompts.Count -eq 0) {
  throw "Config file must contain a non-empty 'prompts' array"
}

# Extract models
$Models = @($config.models)

# Extract prompts into a hashtable for easy lookup
$Prompts = @{}
foreach ($p in $config.prompts) {
  if (-not $p.key) { throw "Each prompt must have a 'key' property" }
  if (-not $p.text) { throw "Prompt '$($p.key)' must have a 'text' property" }
  
  # Use PSObject.Properties to safely check for optional input_file
  $inputFile = $null
  if ($p.PSObject.Properties.Name -contains 'input_file') {
    $inputFile = $p.input_file
  }
  
  $Prompts[$p.key] = @{
    text = $p.text
    input_file = $inputFile
  }
}

# Extract settings with defaults
$configSettings = if ($config.settings) { $config.settings } else { @{} }
$warmupPromptKey = if ($configSettings.warmup_prompt_key) { $configSettings.warmup_prompt_key } else { ($config.prompts | Select-Object -First 1).key }

# Apply settings (command line overrides config file)
if ($RepeatCount -eq -1) {
  $RepeatCount = if ($configSettings.repeat_count) { [int]$configSettings.repeat_count } else { 3 }
}
if ($SmiIntervalSeconds -eq -1) {
  $SmiIntervalSeconds = if ($configSettings.smi_interval_seconds) { [int]$configSettings.smi_interval_seconds } else { 1 }
}
$WarmupCount = if ($configSettings.warmup_count) { [int]$configSettings.warmup_count } else { 1 }

# Quick test mode overrides
if ($QuickTest) {
  $Models = @($Models[0])  # First model only
  $RepeatCount = 1
  Write-Host "=== QUICK TEST MODE ===" -ForegroundColor Yellow
  Write-Host "Running: 1 model ($($Models[0])), $($Prompts.Count) prompts, 1 repeat" -ForegroundColor Yellow
  Write-Host ""
}

# Model override
if (-not [string]::IsNullOrWhiteSpace($ModelOverride)) {
  $Models = $ModelOverride -split ',' | ForEach-Object { $_.Trim() }
  Write-Host "Model override: $($Models -join ', ')" -ForegroundColor Cyan
}

# Display config summary
$modeType = if ($FreshMode) { "Fresh (ollama stop between repeats)" } else { "Steady State (model stays loaded)" }
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Models: $($Models -join ', ')"
Write-Host "  Prompts: $($Prompts.Keys -join ', ')"
Write-Host "  Repeats: $RepeatCount"
Write-Host "  Warmups: $WarmupCount"
Write-Host "  SMI Interval: ${SmiIntervalSeconds}s"
Write-Host "  Benchmark Mode: $modeType" -ForegroundColor $(if ($FreshMode) { "Yellow" } else { "Green" })
Write-Host ""

# ---------------------------
# Helper functions
# ---------------------------
function Ensure-Dir([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Resolve-FullPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

# Convert duration strings to seconds
# Handles: "123.45ms", "1.234s", "3m20.1764161s", "1h2m3.4s"
function ConvertTo-Seconds([string]$s) {
  if (-not $s) { return $null }
  $s = $s.Trim()
  
  # Try hours/minutes/seconds format: 1h2m3.4s, 3m20.5s, etc.
  if ($s -match '^(?:(?<h>\d+)h)?(?:(?<m>\d+)m)?(?<sec>[0-9.]+)s$') {
    $hours = if ($Matches['h']) { [double]$Matches['h'] } else { 0 }
    $mins  = if ($Matches['m']) { [double]$Matches['m'] } else { 0 }
    $secs  = [double]$Matches['sec']
    return ($hours * 3600) + ($mins * 60) + $secs
  }
  
  # Try milliseconds: 123.45ms
  if ($s -match '^(?<val>[0-9.]+)ms$') {
    return [double]$Matches['val'] / 1000.0
  }
  
  # Try plain seconds: 1.234s
  if ($s -match '^(?<val>[0-9.]+)s$') {
    return [double]$Matches['val']
  }
  
  return $null
}

function Test-LogComplete([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $txt = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($txt)) { return $false }
  return ($txt -match 'total duration:\s*' -and $txt -match '(?:^|\n)\s*eval rate:\s*')
}

function Write-RunHeader([string]$Path, [string]$ModeLabel, [string]$BenchmarkMode = "") {
  Ensure-Dir (Split-Path -Parent $Path)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("=== RUN HEADER ===")
  $lines.Add("Timestamp: " + (Get-Date -Format o))
  $lines.Add("Mode: $ModeLabel")
  $lines.Add("Config: $configPath")
  if ($BenchmarkMode) { $lines.Add("Benchmark Mode: $BenchmarkMode") }
  $lines.Add("")
  $lines.Add("nvidia-smi:")
  try { 
    $smiOutput = nvidia-smi 2>&1
    if ($smiOutput) {
      $lines.AddRange([string[]]@($smiOutput | ForEach-Object { $_.ToString() }))
    }
  } catch { 
    $lines.Add("FAILED: nvidia-smi: $_") 
  }
  $lines.Add("")
  $lines.Add("ollama --version:")
  try { $lines.Add((ollama --version)) } catch { $lines.Add("FAILED: ollama --version: $_") }
  $lines.Add("==================")
  $lines.Add("")
  [System.IO.File]::WriteAllText($Path, ($lines -join "`r`n"), [System.Text.Encoding]::UTF8)
}

function Start-NvidiaSmiLogger([string]$OutFile, [int]$IntervalSeconds) {
  Ensure-Dir (Split-Path -Parent $OutFile)

  # Write the logger script to a temp file to avoid escaping nightmares
  $scriptPath = Join-Path ([System.IO.Path]::GetTempPath()) "nvidia-smi-logger-$([Guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
  
  $scriptContent = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$outFile = '$($OutFile -replace "'", "''")'
`$startMsg = "=== NVIDIA-SMI LOG START: " + (Get-Date -Format o) + " ===" + [Environment]::NewLine
[System.IO.File]::AppendAllText(`$outFile, `$startMsg, [System.Text.Encoding]::UTF8)
while (`$true) {
  `$ts = Get-Date -Format o
  `$s = (nvidia-smi | Out-String)
  `$msg = "--- SAMPLE: `$ts ---" + [Environment]::NewLine + `$s + [Environment]::NewLine
  [System.IO.File]::AppendAllText(`$outFile, `$msg, [System.Text.Encoding]::UTF8)
  Start-Sleep -Seconds $IntervalSeconds
}
"@
  
  [System.IO.File]::WriteAllText($scriptPath, $scriptContent, [System.Text.Encoding]::UTF8)

  Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) `
    -WindowStyle Normal `
    -PassThru
}

function Run-OllamaPrompt([string]$Model, [string]$PromptText, [string]$InputFile, [string]$OutFile) {
  Ensure-Dir (Split-Path -Parent $OutFile)

  if ($InputFile) {
    # Prompt with input file: prepend file content to prompt
    $inputPath = Resolve-FullPath $InputFile
    if (-not (Test-Path $inputPath)) { throw "Input file not found: $inputPath" }
    $doc = Get-Content -Path $inputPath -Raw
    $fullPrompt = $doc + "`n`n" + $PromptText

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
      $fullPrompt | Out-File -FilePath $tmp -Encoding utf8
      # Always use --verbose to capture detailed timing info
      $cmd = "type ""$tmp"" | ollama run $Model --verbose > ""$OutFile"" 2>&1"
      cmd.exe /c $cmd | Out-Null
    }
    finally {
      Remove-Item -Force -ErrorAction SilentlyContinue $tmp
    }
  }
  else {
    # Simple prompt - always use --verbose
    $escapedPrompt = $PromptText.Replace('"', '\"')
    $cmd = "ollama run $Model --verbose ""$escapedPrompt"" > ""$OutFile"" 2>&1"
    cmd.exe /c $cmd | Out-Null
  }
}

function Stop-OllamaModel([string]$Model) {
  # Unload model from Ollama to get fresh-load performance on next run
  try {
    $result = ollama stop $Model 2>&1
    # Give Ollama a moment to release GPU memory
    Start-Sleep -Milliseconds 500
  } catch {
    # Model might not be loaded, that's OK
  }
}

function Parse-OllamaLog([string]$Path) {
  if (-not (Test-Path $Path)) { return $null }
  $txt = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($txt)) { return $null }

  function GetV([string]$pattern) {
    $m = [regex]::Match($txt, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($m.Success) { return $m.Groups["v"].Value.Trim() }
    return $null
  }

  $durPattern = '(?<v>(?:\d+h)?(?:\d+m)?[0-9.]+(?:ms|s))'

  $totalDurRaw = GetV "total duration:\s*$durPattern"
  $loadDurRaw  = GetV "load duration:\s*$durPattern"
  $peCountRaw  = GetV 'prompt eval count:\s*(?<v>\d+)'
  $peDurRaw    = GetV "prompt eval duration:\s*$durPattern"
  $peRateRaw   = GetV 'prompt eval rate:\s*(?<v>[0-9.]+)\s*tokens/s'
  $eCountRaw   = GetV '^\s*eval count:\s*(?<v>\d+)'
  $eDurRaw     = GetV "^\s*eval duration:\s*$durPattern"
  $eRateRaw    = GetV '^\s*eval rate:\s*(?<v>[0-9.]+)\s*tokens/s'

  [pscustomobject]@{
    total_duration_s        = ConvertTo-Seconds $totalDurRaw
    load_duration_s         = ConvertTo-Seconds $loadDurRaw
    prompt_eval_count       = if ($peCountRaw) { [int]$peCountRaw } else { $null }
    prompt_eval_duration_s  = ConvertTo-Seconds $peDurRaw
    prompt_eval_rate_tps    = if ($peRateRaw) { [double]$peRateRaw } else { $null }
    eval_count              = if ($eCountRaw) { [int]$eCountRaw } else { $null }
    eval_duration_s         = ConvertTo-Seconds $eDurRaw
    eval_rate_tps           = if ($eRateRaw) { [double]$eRateRaw } else { $null }
  }
}

function Get-GpuMetricsForWindow([string]$SmiLogPath, [datetime]$StartTime, [datetime]$EndTime) {
  if (-not (Test-Path $SmiLogPath)) {
    return [pscustomobject]@{
      gpu_mem_max_mb = $null
      gpu_mem_min_mb = $null
      gpu_util_max_pct = $null
      gpu_util_mean_pct = $null
      gpu_power_max_w = $null
      gpu_power_mean_w = $null
      gpu_temp_max_c = $null
      gpu_samples = 0
    }
  }
  
  $content = Get-Content -Path $SmiLogPath -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($content)) {
    return [pscustomobject]@{
      gpu_mem_max_mb = $null
      gpu_mem_min_mb = $null
      gpu_util_max_pct = $null
      gpu_util_mean_pct = $null
      gpu_power_max_w = $null
      gpu_power_mean_w = $null
      gpu_temp_max_c = $null
      gpu_samples = 0
    }
  }
  
  $samples = $content -split '--- SAMPLE: '
  
  $memValues = @()
  $utilValues = @()
  $powerValues = @()
  $tempValues = @()
  
  foreach ($sample in $samples) {
    if ([string]::IsNullOrWhiteSpace($sample)) { continue }
    
    if ($sample -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*)') {
      try {
        $sampleTime = [datetime]::Parse($Matches[1])
        
        if ($sampleTime -ge $StartTime -and $sampleTime -le $EndTime) {
          if ($sample -match '(\d+)MiB\s*/\s*\d+MiB') {
            $memValues += [int]$Matches[1]
          }
          if ($sample -match '(\d+)%\s+Default') {
            $utilValues += [int]$Matches[1]
          }
          if ($sample -match '(\d+)W\s*/\s*\d+W') {
            $powerValues += [int]$Matches[1]
          }
          if ($sample -match '(\d+)C\s+P[0-8]') {
            $tempValues += [int]$Matches[1]
          }
        }
      } catch { }
    }
  }
  
  [pscustomobject]@{
    gpu_mem_max_mb = if ($memValues.Count -gt 0) { ($memValues | Measure-Object -Maximum).Maximum } else { $null }
    gpu_mem_min_mb = if ($memValues.Count -gt 0) { ($memValues | Measure-Object -Minimum).Minimum } else { $null }
    gpu_util_max_pct = if ($utilValues.Count -gt 0) { ($utilValues | Measure-Object -Maximum).Maximum } else { $null }
    gpu_util_mean_pct = if ($utilValues.Count -gt 0) { [Math]::Round(($utilValues | Measure-Object -Average).Average, 1) } else { $null }
    gpu_power_max_w = if ($powerValues.Count -gt 0) { ($powerValues | Measure-Object -Maximum).Maximum } else { $null }
    gpu_power_mean_w = if ($powerValues.Count -gt 0) { [Math]::Round(($powerValues | Measure-Object -Average).Average, 1) } else { $null }
    gpu_temp_max_c = if ($tempValues.Count -gt 0) { ($tempValues | Measure-Object -Maximum).Maximum } else { $null }
    gpu_samples = $memValues.Count
  }
}

function Get-Stats([double[]]$Values) {
  if (-not $Values -or $Values.Count -eq 0) {
    return [pscustomobject]@{
      count  = 0
      mean   = $null
      stddev = $null
      min    = $null
      max    = $null
      median = $null
      cv_pct = $null
    }
  }
  
  $sorted = $Values | Sort-Object
  $count = $Values.Count
  $sum = ($Values | Measure-Object -Sum).Sum
  $mean = $sum / $count
  
  $sumSqDiff = 0
  foreach ($v in $Values) {
    $sumSqDiff += [Math]::Pow($v - $mean, 2)
  }
  $stddev = if ($count -gt 1) { [Math]::Sqrt($sumSqDiff / ($count - 1)) } else { 0 }
  
  $median = if ($count % 2 -eq 0) {
    ($sorted[$count/2 - 1] + $sorted[$count/2]) / 2
  } else {
    $sorted[[Math]::Floor($count/2)]
  }
  
  $cv = if ($mean -ne 0) { ($stddev / $mean) * 100 } else { $null }
  
  [pscustomobject]@{
    count  = $count
    mean   = [Math]::Round($mean, 4)
    stddev = [Math]::Round($stddev, 4)
    min    = [Math]::Round(($sorted | Select-Object -First 1), 4)
    max    = [Math]::Round(($sorted | Select-Object -Last 1), 4)
    median = [Math]::Round($median, 4)
    cv_pct = if ($cv) { [Math]::Round($cv, 2) } else { $null }
  }
}

function Export-SummaryStats([System.Collections.Generic.List[object]]$Results, [string]$CsvPath) {
  $summaryPath = $CsvPath -replace '\.csv$', '-summary.csv'
  
  $summaryRows = New-Object System.Collections.Generic.List[object]
  
  $groups = $Results | Group-Object -Property model, prompt
  
  foreach ($group in $groups) {
    $model = $group.Group[0].model
    $prompt = $group.Group[0].prompt
    
    $totalDurations = @($group.Group | Where-Object { $null -ne $_.total_duration_s } | ForEach-Object { $_.total_duration_s })
    $evalRates = @($group.Group | Where-Object { $null -ne $_.eval_rate_tps } | ForEach-Object { $_.eval_rate_tps })
    $peRates = @($group.Group | Where-Object { $null -ne $_.prompt_eval_rate_tps } | ForEach-Object { $_.prompt_eval_rate_tps })
    $evalCounts = @($group.Group | Where-Object { $null -ne $_.eval_count } | ForEach-Object { $_.eval_count })
    $gpuMemMax = @($group.Group | Where-Object { $null -ne $_.gpu_mem_max_mb } | ForEach-Object { $_.gpu_mem_max_mb })
    $gpuPowerMax = @($group.Group | Where-Object { $null -ne $_.gpu_power_max_w } | ForEach-Object { $_.gpu_power_max_w })
    
    $totalStats = Get-Stats $totalDurations
    $evalRateStats = Get-Stats $evalRates
    $peRateStats = Get-Stats $peRates
    $evalCountStats = Get-Stats $evalCounts
    $gpuMemStats = Get-Stats $gpuMemMax
    $gpuPowerStats = Get-Stats $gpuPowerMax
    
    $row = [pscustomobject]@{
      model = $model
      prompt = $prompt
      runs = $group.Count
      
      eval_rate_mean = $evalRateStats.mean
      eval_rate_stddev = $evalRateStats.stddev
      eval_rate_min = $evalRateStats.min
      eval_rate_max = $evalRateStats.max
      eval_rate_cv_pct = $evalRateStats.cv_pct
      
      prompt_eval_rate_mean = $peRateStats.mean
      prompt_eval_rate_stddev = $peRateStats.stddev
      prompt_eval_rate_min = $peRateStats.min
      prompt_eval_rate_max = $peRateStats.max
      
      total_duration_mean = $totalStats.mean
      total_duration_stddev = $totalStats.stddev
      total_duration_min = $totalStats.min
      total_duration_max = $totalStats.max
      
      eval_count_mean = $evalCountStats.mean
      eval_count_min = $evalCountStats.min
      eval_count_max = $evalCountStats.max
      
      gpu_mem_max_mb = $gpuMemStats.max
      gpu_power_max_w = $gpuPowerStats.max
      
      high_variance = if ($evalRateStats.cv_pct -and $evalRateStats.cv_pct -gt 10) { "YES" } else { "" }
    }
    
    $summaryRows.Add($row)
  }
  
  # Model-level summary
  $modelGroups = $Results | Group-Object -Property model
  foreach ($mg in $modelGroups) {
    $model = $mg.Group[0].model
    $evalRates = @($mg.Group | Where-Object { $null -ne $_.eval_rate_tps } | ForEach-Object { $_.eval_rate_tps })
    $peRates = @($mg.Group | Where-Object { $null -ne $_.prompt_eval_rate_tps } | ForEach-Object { $_.prompt_eval_rate_tps })
    $gpuMemMax = @($mg.Group | Where-Object { $null -ne $_.gpu_mem_max_mb } | ForEach-Object { $_.gpu_mem_max_mb })
    $gpuPowerMax = @($mg.Group | Where-Object { $null -ne $_.gpu_power_max_w } | ForEach-Object { $_.gpu_power_max_w })
    
    $evalRateStats = Get-Stats $evalRates
    $peRateStats = Get-Stats $peRates
    $gpuMemStats = Get-Stats $gpuMemMax
    $gpuPowerStats = Get-Stats $gpuPowerMax
    
    $row = [pscustomobject]@{
      model = $model
      prompt = "ALL"
      runs = $mg.Count
      
      eval_rate_mean = $evalRateStats.mean
      eval_rate_stddev = $evalRateStats.stddev
      eval_rate_min = $evalRateStats.min
      eval_rate_max = $evalRateStats.max
      eval_rate_cv_pct = $evalRateStats.cv_pct
      
      prompt_eval_rate_mean = $peRateStats.mean
      prompt_eval_rate_stddev = $peRateStats.stddev
      prompt_eval_rate_min = $peRateStats.min
      prompt_eval_rate_max = $peRateStats.max
      
      total_duration_mean = $null
      total_duration_stddev = $null
      total_duration_min = $null
      total_duration_max = $null
      
      eval_count_mean = $null
      eval_count_min = $null
      eval_count_max = $null
      
      gpu_mem_max_mb = $gpuMemStats.max
      gpu_power_max_w = $gpuPowerStats.max
      
      high_variance = if ($evalRateStats.cv_pct -and $evalRateStats.cv_pct -gt 10) { "YES" } else { "" }
    }
    
    $summaryRows.Add($row)
  }
  
  $summaryRows | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding utf8
  return $summaryPath
}

# ---------------------------
# Main execution
# ---------------------------
Ensure-Dir (Resolve-FullPath $LogDir)

$runRoot =
  if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Resolve-FullPath (Join-Path $LogDir "$stamp-$Mode")
  } else {
    Resolve-FullPath $RunRoot
  }

Ensure-Dir $runRoot

$summaryFile = Join-Path $runRoot ("run-summary-{0}.txt" -f $Mode)
$csvPath     = Join-Path $runRoot ("ollama-results-{0}.csv" -f $Mode)
$smiLog      = Join-Path $runRoot ("nvidia-smi-{0}_log.txt" -f $Mode)

Ensure-Dir (Split-Path -Parent $summaryFile)
Ensure-Dir (Split-Path -Parent $csvPath)
Ensure-Dir (Split-Path -Parent $smiLog)

# Copy config file to run folder for reproducibility
$configCopy = Join-Path $runRoot "config.json"
Copy-Item -Path $configPath -Destination $configCopy -Force

$benchmarkModeLabel = if ($FreshMode) { "Fresh (ollama stop between repeats)" } else { "Steady State (model stays loaded)" }

if (-not (Test-Path $summaryFile)) {
  Write-RunHeader -Path $summaryFile -ModeLabel $Mode -BenchmarkMode $benchmarkModeLabel
} else {
  [System.IO.File]::AppendAllText($summaryFile, "`r`n=== RESUME: $(Get-Date -Format o) ===`r`nBenchmark Mode: $benchmarkModeLabel`r`n", [System.Text.Encoding]::UTF8)
}

$smiProc = Start-NvidiaSmiLogger -OutFile $smiLog -IntervalSeconds $SmiIntervalSeconds

$results = New-Object System.Collections.Generic.List[object]

Start-Sleep -Milliseconds 500

try {
  $totalModels = $Models.Count
  $modelIndex = 0
  
  foreach ($m in $Models) {
    $modelIndex++
    $modelSafe = $m.Replace(":", "_")
    $modelDir = Join-Path $runRoot $modelSafe
    Ensure-Dir $modelDir

    Write-Host "`n[$modelIndex/$totalModels] Model: $m" -ForegroundColor Cyan

    $hdr = Join-Path $modelDir ("00-header-{0}-{1}.txt" -f $Mode, $modelSafe)
    if (-not (Test-Path $hdr)) { Write-RunHeader -Path $hdr -ModeLabel "$Mode / $m" -BenchmarkMode $benchmarkModeLabel }

    # Warmup runs - run multiple times to reach steady state
    $warmupPrompt = $Prompts[$warmupPromptKey]
    for ($w = 1; $w -le $WarmupCount; $w++) {
      $warm = Join-Path $modelDir ("00-warmup{0:00}-{1}-{2}-{3}.txt" -f $w, $warmupPromptKey, $Mode, $modelSafe)
      if (-not ($Resume -and (Test-LogComplete $warm))) { 
        Write-Host "  Warmup $w/$WarmupCount..." -ForegroundColor DarkGray -NoNewline
        Run-OllamaPrompt $m $warmupPrompt.text $warmupPrompt.input_file $warm
        
        # Parse and display warmup performance to track stabilization
        $warmParsed = Parse-OllamaLog $warm
        if ($warmParsed -and $warmParsed.eval_rate_tps) {
          Write-Host " $([Math]::Round($warmParsed.eval_rate_tps, 1)) tok/s" -ForegroundColor DarkGray
        } else {
          Write-Host " done" -ForegroundColor DarkGray
        }
      } else {
        Write-Host "  Warmup $w/$WarmupCount... (cached)" -ForegroundColor DarkGray
      }
    }

    for ($i=1; $i -le $RepeatCount; $i++) {

      # In FreshMode, stop the model before each repeat to ensure fresh-load performance
      if ($FreshMode) {
        Write-Host "  [Fresh Mode] Stopping model before repeat $i..." -ForegroundColor Yellow
        Stop-OllamaModel $m
      }

      foreach ($promptKey in $Prompts.Keys | Sort-Object) {
        $promptDef = $Prompts[$promptKey]
        $outFile = Join-Path $modelDir ("{0}-r{1:00}-{2}-{3}.txt" -f $promptKey, $i, $Mode, $modelSafe)
        
        $ran = $false
        $runStart = $null
        $runEnd = $null
        
        if (-not ($Resume -and (Test-LogComplete $outFile))) {
          Write-Host "  Run $i - Prompt $promptKey..." -ForegroundColor DarkGray -NoNewline
          $runStart = Get-Date
          Run-OllamaPrompt $m $promptDef.text $promptDef.input_file $outFile
          $runEnd = Get-Date
          $ran = $true
          Write-Host " done" -ForegroundColor DarkGray
        } else {
          Write-Host "  Run $i - Prompt $promptKey... (cached)" -ForegroundColor DarkGray
        }

        $parsed = Parse-OllamaLog $outFile

        $row = [pscustomobject]@{
          benchmark_mode = if ($FreshMode) { "fresh" } else { "steady" }
          mode          = $Mode
          model         = $m
          prompt        = $promptKey
          repeat_index  = $i
          log_file      = $outFile
          ran_this_time = $ran
          run_start     = if ($runStart) { $runStart.ToString("o") } else { $null }
          run_end       = if ($runEnd) { $runEnd.ToString("o") } else { $null }
        }

        if ($parsed) {
          foreach ($p in $parsed.PSObject.Properties) {
            $row | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
          }
        }

        # GPU metrics for this run
        if ($runStart -and $runEnd) {
          $gpuMetrics = Get-GpuMetricsForWindow $smiLog $runStart $runEnd
          $row | Add-Member -NotePropertyName "gpu_mem_max_mb" -NotePropertyValue $gpuMetrics.gpu_mem_max_mb
          $row | Add-Member -NotePropertyName "gpu_mem_min_mb" -NotePropertyValue $gpuMetrics.gpu_mem_min_mb
          $row | Add-Member -NotePropertyName "gpu_util_max_pct" -NotePropertyValue $gpuMetrics.gpu_util_max_pct
          $row | Add-Member -NotePropertyName "gpu_util_mean_pct" -NotePropertyValue $gpuMetrics.gpu_util_mean_pct
          $row | Add-Member -NotePropertyName "gpu_power_max_w" -NotePropertyValue $gpuMetrics.gpu_power_max_w
          $row | Add-Member -NotePropertyName "gpu_power_mean_w" -NotePropertyValue $gpuMetrics.gpu_power_mean_w
          $row | Add-Member -NotePropertyName "gpu_temp_max_c" -NotePropertyValue $gpuMetrics.gpu_temp_max_c
          $row | Add-Member -NotePropertyName "gpu_samples" -NotePropertyValue $gpuMetrics.gpu_samples
        }

        # Parse warnings
        if ($parsed) {
          $suspicious = @()
          if ($null -eq $parsed.total_duration_s) { $suspicious += "missing_total_duration" }
          if ($null -eq $parsed.eval_rate_tps) { $suspicious += "missing_eval_rate" }
          if ($parsed.prompt_eval_count -eq $parsed.eval_count -and $parsed.prompt_eval_count -gt 0) {
            if ($parsed.prompt_eval_rate_tps -eq $parsed.eval_rate_tps) {
              $suspicious += "possible_parse_collision"
            }
          }
          $row | Add-Member -NotePropertyName "parse_warnings" -NotePropertyValue ($suspicious -join ";")
        }

        $results.Add($row) | Out-Null
      }
    }
  }

  # Export results
  $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8
  $statsCsvPath = Export-SummaryStats $results $csvPath
  
  [System.IO.File]::AppendAllText($summaryFile, "`r`n=== RUN COMPLETE: $(Get-Date -Format o) ===`r`nCSV: $csvPath`r`nSummary: $statsCsvPath`r`n", [System.Text.Encoding]::UTF8)
  
  Write-Host "`n=== RUN COMPLETE ===" -ForegroundColor Green
  Write-Host "Raw results: $csvPath"
  Write-Host "Summary stats: $statsCsvPath"
  Write-Host "Config copy: $configCopy"
}
finally {
  if ($smiProc -and -not $smiProc.HasExited) {
    Stop-Process -Id $smiProc.Id -Force -ErrorAction SilentlyContinue
  }
}