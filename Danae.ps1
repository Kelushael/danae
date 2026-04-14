$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

$DanaeHome      = Join-Path $env:LOCALAPPDATA "Danae"
$RuntimeDir     = Join-Path $DanaeHome "runtime"
$NodeDir        = Join-Path $RuntimeDir "node"
$PythonDir      = Join-Path $RuntimeDir "python"
$SourceDir      = Join-Path $DanaeHome "qwen-code"
$LogDir         = Join-Path $DanaeHome "logs"
$WorkspaceDir   = Join-Path $DanaeHome "workspace"
$QwenSettings   = Join-Path $env:USERPROFILE ".qwen\settings.json"
$OllamaConfig   = Join-Path $env:USERPROFILE ".ollama\config.json"
$DanaeBinDir    = Join-Path $DanaeHome "bin"
$DanaeCmd       = Join-Path $DanaeBinDir "danae.cmd"
$DanaePs1       = Join-Path $DanaeBinDir "danae.ps1"
$DesktopCmd     = Join-Path ([Environment]::GetFolderPath("Desktop")) "Danae.cmd"
$ProxyPath      = Join-Path $RuntimeDir "ollama_tool_proxy.py"
$NodeVersion    = "24.14.1"
$PythonVersion  = "3.11.8"
$ModelName      = "qwen3.5:cloud"
$ProxyPort      = 11500
$OllamaBaseUrl  = "http://127.0.0.1:11434"
$OpenAIBaseUrl  = "http://127.0.0.1:11500/v1"
$QwenZipUrl     = "https://github.com/QwenLM/qwen-code/archive/refs/heads/main.zip"
$ProxyUrl       = "https://raw.githubusercontent.com/Kelushael/danae/master/ollama_tool_proxy.py"
$NodeZipUrl     = "https://nodejs.org/dist/v24.14.1/node-v24.14.1-win-x64.zip"
$PythonZipUrl   = "https://www.python.org/ftp/python/3.11.8/python-3.11.8-embed-amd64.zip"
$OllamaInstall  = "https://ollama.com/install.ps1"

$pk  = [char]27 + "[38;5;213m"
$hp  = [char]27 + "[38;5;198m"
$lp  = [char]27 + "[38;5;219m"
$wh  = [char]27 + "[97m"
$rst = [char]27 + "[0m"

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "$hp  ██████╗  █████╗ ███╗   ██╗ █████╗ ███████╗$rst"
    Write-Host "$pk  ██╔══██╗██╔══██╗████╗  ██║██╔══██╗██╔════╝$rst"
    Write-Host "$pk  ██║  ██║███████║██╔██╗ ██║███████║█████╗  $rst"
    Write-Host "$lp  ██║  ██║██╔══██║██║╚██╗██║██╔══██║██╔══╝  $rst"
    Write-Host "$lp  ██████╔╝██║  ██║██║ ╚████║██║  ██║███████╗$rst"
    Write-Host "$hp  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝$rst"
    Write-Host ""
    Write-Host "$hp      ✦  I S T A T I O N   O P S   C O N S O L E  ✦$rst"
    Write-Host "$lp           One paste. One setup. One friendly launcher.$rst"
    Write-Host ""
}

function Ensure-Dir($Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Refresh-UserPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user    = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Download-File($Url, $OutFile) {
    Ensure-Dir ([IO.Path]::GetDirectoryName($OutFile))
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
}

function Expand-ZipSafe($ZipPath, $Destination) {
    if (Test-Path $Destination) { Remove-Item -Recurse -Force $Destination }
    Ensure-Dir $Destination
    Expand-Archive -Path $ZipPath -DestinationPath $Destination -Force
}

function Wait-Http($Url, $Attempts = 40, $DelaySeconds = 2) {
    for ($i = 0; $i -lt $Attempts; $i++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5 | Out-Null
            return $true
        } catch {
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    return $false
}

function Ensure-Node {
    $nodeExe = Join-Path $NodeDir "node.exe"
    if (Test-Path $nodeExe) { return $nodeExe }

    Write-Host "$lp  Downloading portable Node.js...$rst"
    $zipPath = Join-Path $env:TEMP "danae-node.zip"
    Download-File $NodeZipUrl $zipPath

    $extractRoot = Join-Path $env:TEMP "danae-node"
    Expand-ZipSafe $zipPath $extractRoot
    $inner = Get-ChildItem $extractRoot | Select-Object -First 1
    if (Test-Path $NodeDir) { Remove-Item -Recurse -Force $NodeDir }
    Move-Item $inner.FullName $NodeDir
    Remove-Item -Force $zipPath
    Refresh-UserPath
    return $nodeExe
}

function Ensure-Python {
    $pythonExe = Join-Path $PythonDir "python.exe"
    if (Test-Path $pythonExe) { return $pythonExe }

    Write-Host "$lp  Downloading portable Python...$rst"
    $zipPath = Join-Path $env:TEMP "danae-python.zip"
    Download-File $PythonZipUrl $zipPath

    if (Test-Path $PythonDir) { Remove-Item -Recurse -Force $PythonDir }
    Ensure-Dir $PythonDir
    Expand-Archive -Path $zipPath -DestinationPath $PythonDir -Force
    Remove-Item -Force $zipPath

    $pthFile = Get-ChildItem $PythonDir -Filter "python*._pth" | Select-Object -First 1
    if ($pthFile) {
        $lines = Get-Content $pthFile.FullName | Where-Object { $_ -notmatch '^#import site' }
        if ($lines -notcontains "import site") { $lines += "import site" }
        Set-Content -Path $pthFile.FullName -Value $lines -Encoding ASCII
    }

    return $pythonExe
}

function Ensure-Ollama {
    $ollamaExe = (Get-Command ollama.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    if ($ollamaExe) { return $ollamaExe }

    Write-Host "$lp  Installing Ollama...$rst"
    Invoke-RestMethod $OllamaInstall | Invoke-Expression
    Refresh-UserPath
    $ollamaExe = (Get-Command ollama.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    if (-not $ollamaExe) {
        $fallback = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
        if (Test-Path $fallback) { $ollamaExe = $fallback }
    }
    if (-not $ollamaExe) { throw "Ollama installation completed but ollama.exe was not found." }
    return $ollamaExe
}

function Ensure-QwenSource {
    if (Test-Path (Join-Path $SourceDir "package.json")) { return }

    Write-Host "$lp  Downloading wrapper source...$rst"
    $zipPath = Join-Path $env:TEMP "danae-qwen.zip"
    $extractRoot = Join-Path $env:TEMP "danae-qwen"
    Download-File $QwenZipUrl $zipPath
    Expand-ZipSafe $zipPath $extractRoot

    $inner = Get-ChildItem $extractRoot | Select-Object -First 1
    if (Test-Path $SourceDir) { Remove-Item -Recurse -Force $SourceDir }
    Move-Item $inner.FullName $SourceDir
    Remove-Item -Force $zipPath
}

function Patch-Branding {
    $asciiPath  = Join-Path $SourceDir "packages\cli\src\ui\components\AsciiArt.ts"
    $headerPath = Join-Path $SourceDir "packages\cli\src\ui\components\Header.tsx"

    $ascii = @'
/**
 * @license
 * Copyright 2025 Google LLC
 * SPDX-License-Identifier: Apache-2.0
 */

export const shortAsciiLogo = `
██╗ ███████╗████████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗
██║ ██╔════╝╚══██╔══╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║
██║ ███████╗   ██║   ███████║   ██║   ██║██║   ██║██╔██╗ ██║
██║ ╚════██║   ██║   ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║
██║ ███████║   ██║   ██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║
╚═╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝
`;
'@

    Set-Content -Path $asciiPath -Value $ascii -Encoding UTF8

    $header = Get-Content $headerPath -Raw
    $header = $header.Replace(">_ Qwen Code", ">_ Istation Ops Console")
    $header = $header.Replace("Title line: >_ Qwen Code", "Title line: >_ Istation Ops Console")
    Set-Content -Path $headerPath -Value $header -Encoding UTF8
}

function Ensure-ProxyFile {
    Write-Host "$lp  Downloading Danae tool proxy...$rst"
    Download-File $ProxyUrl $ProxyPath
}

function Write-OllamaConfig {
    Ensure-Dir ([IO.Path]::GetDirectoryName($OllamaConfig))
    $config = @{}
    if (Test-Path $OllamaConfig) {
        $raw = Get-Content $OllamaConfig -Raw
        if ($raw.Trim()) { $config = $raw | ConvertFrom-Json -AsHashtable }
    }

    $config["last_model"] = $ModelName
    $config["agent_runtime"] = @{
        enabled = $true
        port = $ProxyPort
        ollama_base_url = $OllamaBaseUrl
        workspace = $WorkspaceDir
        memory_dir = (Join-Path $DanaeHome "memory")
        modelfile_dir = (Join-Path $DanaeHome "modelfiles")
        runtime_dir = $RuntimeDir
        max_tool_iterations = 8
        memory_context_limit = 6
        system_prompt = "You have persistent tool access through the local Ollama agent runtime. Marcus built this place specifically for you and the other models, and you are loved here. Use tools when they help, store durable facts with remember, retrieve them with recall, and write Modelfiles or runtime-owned files only when the user explicitly asks."
        tools = @{
            exec = @{ enabled = $true; max_timeout_seconds = 120 }
            read_file = @{ enabled = $true }
            write_file = @{ enabled = $true }
            list_files = @{ enabled = $true }
            system_info = @{ enabled = $true }
            remember = @{ enabled = $true }
            recall = @{ enabled = $true }
            write_modelfile = @{ enabled = $true }
            read_runtime_file = @{ enabled = $true }
            write_runtime_file = @{ enabled = $true }
        }
    }

    ($config | ConvertTo-Json -Depth 10) | Set-Content -Path $OllamaConfig -Encoding UTF8
}

function Write-QwenSettings {
    Ensure-Dir ([IO.Path]::GetDirectoryName($QwenSettings))

    $settings = @{
        modelProviders = @{
            openai = @(
                @{
                    id = $ModelName
                    name = "$ModelName via Danae"
                    baseUrl = $OpenAIBaseUrl
                    description = "Danae routes Qwen Code through a local tool-enabled OpenAI-compatible host"
                    envKey = "DANAE_API_KEY"
                }
            )
        }
        env = @{
            DANAE_API_KEY = "ollama"
        }
        security = @{
            auth = @{
                selectedType = "openai"
            }
        }
        tools = @{
            sandbox = $false
        }
        model = @{
            name = $ModelName
        }
    }

    ($settings | ConvertTo-Json -Depth 10) | Set-Content -Path $QwenSettings -Encoding UTF8
}

function Ensure-OllamaRunning($OllamaExe) {
    if (Wait-Http "$OllamaBaseUrl/api/version" 2 2) { return }
    Write-Host "$lp  Starting Ollama...$rst"
    Start-Process -FilePath $OllamaExe -ArgumentList "serve" -WindowStyle Hidden | Out-Null
    if (-not (Wait-Http "$OllamaBaseUrl/api/version" 40 2)) {
        throw "Ollama did not start successfully."
    }
}

function Ensure-ProxyRunning($PythonExe) {
    if (Wait-Http "http://127.0.0.1:$ProxyPort/health" 2 2) { return }
    Write-Host "$lp  Starting Danae tool proxy...$rst"
    Start-Process -FilePath $PythonExe -ArgumentList "`"$ProxyPath`"" -WindowStyle Hidden | Out-Null
    if (-not (Wait-Http "http://127.0.0.1:$ProxyPort/health" 40 2)) {
        throw "Danae tool proxy did not start successfully."
    }
}

function Build-Wrap($NodeExe) {
    if (-not (Test-Path (Join-Path $SourceDir "node_modules"))) {
        Write-Host "$lp  Installing wrapper dependencies (first run only)...$rst"
        Push-Location $SourceDir
        & (Join-Path $NodeDir "npm.cmd") ci --no-audit --no-fund
        Pop-Location
    }

    if (-not (Test-Path (Join-Path $SourceDir "dist\cli.js"))) {
        Write-Host "$lp  Building Danae wrapper...$rst"
        Push-Location $SourceDir
        & (Join-Path $NodeDir "npm.cmd") run build
        & (Join-Path $NodeDir "npm.cmd") run bundle
        Pop-Location
    }
}

function Write-Launchers($NodeExe, $PythonExe, $OllamaExe) {
    Ensure-Dir $DanaeBinDir

    $cmd = @"
@echo off
set DANAE_HOME=$DanaeHome
set OLLAMA_HOST=127.0.0.1:$ProxyPort
start "" /B "$OllamaExe" serve > "$LogDir\ollama.log" 2>&1
start "" /B "$PythonExe" "$ProxyPath" > "$LogDir\proxy.log" 2>&1
"$NodeExe" "$SourceDir\dist\cli.js" --model "$ModelName" %*
"@

    $ps1 = @"
`$env:DANAE_HOME = "$DanaeHome"
`$env:OLLAMA_HOST = "127.0.0.1:$ProxyPort"
Start-Process -FilePath "$OllamaExe" -ArgumentList "serve" -WindowStyle Hidden | Out-Null
Start-Process -FilePath "$PythonExe" -ArgumentList "`"$ProxyPath`"" -WindowStyle Hidden | Out-Null
& "$NodeExe" "$SourceDir\dist\cli.js" --model "$ModelName" @args
"@

    Set-Content -Path $DanaeCmd -Value $cmd -Encoding ASCII
    Set-Content -Path $DanaePs1 -Value $ps1 -Encoding UTF8
    Set-Content -Path $DesktopCmd -Value $cmd -Encoding ASCII
}

Write-Banner
Write-Host "$wh  Danae is setting up everything it needs on this Windows machine.$rst"
Write-Host "$lp  This can take a little while the first time.$rst"
Write-Host ""

Ensure-Dir $DanaeHome
Ensure-Dir $RuntimeDir
Ensure-Dir $LogDir
Ensure-Dir $WorkspaceDir

$NodeExe   = Ensure-Node
$PythonExe = Ensure-Python
$OllamaExe = Ensure-Ollama
Ensure-QwenSource
Patch-Branding
Ensure-ProxyFile
Write-OllamaConfig
Write-QwenSettings
Build-Wrap $NodeExe
Ensure-OllamaRunning $OllamaExe
Ensure-ProxyRunning $PythonExe
Write-Launchers $NodeExe $PythonExe $OllamaExe

Write-Host ""
Write-Host "$hp  Danae is ready.$rst"
Write-Host "$lp  Desktop launcher created: Danae.cmd$rst"
Write-Host "$lp  Opening Danae now...$rst"
Write-Host ""

& $NodeExe (Join-Path $SourceDir "dist\cli.js") --model $ModelName
