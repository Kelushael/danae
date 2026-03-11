# SalesOps_AI.ps1
# AI-Native Sales Ops Advisor — Auto-Install Edition

$ErrorActionPreference = "Stop"
$ScriptDir  = $PSScriptRoot
$ModelName  = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
$ModelPath  = Join-Path $ScriptDir $ModelName
$ModelUrl   = "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
$PyScript   = Join-Path $ScriptDir "salesops_chat.py"

# ── ANSI pink (works on Win10+ / PowerShell 5.1+) ──────────────────────────
$pk  = [char]27 + "[38;5;213m"   # soft pink
$hp  = [char]27 + "[38;5;198m"   # hot pink
$lp  = [char]27 + "[38;5;219m"   # light pink / lavender
$wh  = [char]27 + "[97m"         # bright white
$rst = [char]27 + "[0m"

Clear-Host

# ── BUTTERFLY ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "$hp      ██╗    ██╗   ██╗    ██╗$rst"
Write-Host "$hp     ██╔╝╲  ╱██║   ██║╲  ╱╚██╗$rst"
Write-Host "$pk    ██╔╝  ╲╱ ███████████╲  ╚██╗$rst"
Write-Host "$pk   ██╔╝  ╱╲  ╚══════════╝  ╱╚██╗$rst"
Write-Host "$lp  ██╔╝  ╱  ╲   ♥  ♥  ♥   ╱  ╚██╗$rst"
Write-Host "$lp  ╚██║  ╲  ╱   ♥  ♥  ♥   ╲  ╔██╝$rst"
Write-Host "$pk   ╚██╗  ╲╱  ╔══════════╗  ╲╔██╝$rst"
Write-Host "$pk    ╚██╗  ╱╲  ╚══════════╝  ╱╔██╝$rst"
Write-Host "$hp     ╚██╗╱  ╲   ██║   ╱  ╲╔██╝$rst"
Write-Host "$hp      ╚██╝   ╲  ██║  ╱   ╚██╝$rst"
Write-Host "$pk            ╔══╩══╩══╗$rst"
Write-Host "$pk            ║  ♥ ♥ ♥ ║$rst"
Write-Host "$pk            ╚════╦════╝$rst"
Write-Host "$lp                 ║$rst"
Write-Host "$lp               ══╩══$rst"
Write-Host ""
Write-Host "$hp  ✦  ✦  ✦   S A L E S O P S   A I   ✦  ✦  ✦$rst"
Write-Host "$lp        Your AI-Native Operations Advisor$rst"
Write-Host ""
Write-Host "$pk  ──────────────────────────────────────────────$rst"
Write-Host ""

# ── ASK THE OPENING QUESTION ────────────────────────────────────────────────
Write-Host "$wh  Before we set everything up, let's make this yours.$rst"
Write-Host ""
Write-Host "$lp  What is your company's current #1 goal or challenge?$rst"
Write-Host "$pk  (e.g. 'reduce order errors', 'clean up CRM data', 'speed up renewals')$rst"
Write-Host ""
Write-Host -NoNewline "$hp  ➤  $rst"
$UserGoal = Read-Host

Write-Host ""
Write-Host "$pk  ✦ Got it. Building your advisor around that now...$rst"
Write-Host ""

# ── PYTHON: AUTO-INSTALL IF MISSING ────────────────────────────────────────
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

$pythonOk = $false
try {
    $v = python --version 2>&1
    if ($v -match "Python") { $pythonOk = $true }
} catch {}

if (-not $pythonOk) {
    Write-Host "$lp  Python not found — downloading and installing silently...$rst"
    $installer = Join-Path $env:TEMP "python_installer.exe"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe" -OutFile $installer
    Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_test=0" -Wait
    Refresh-Path
    Write-Host "$pk  Python installed.$rst"
} else {
    $v = python --version 2>&1
    Write-Host "$lp  Python ready: $v$rst"
}

# ── PIP DEPENDENCIES ────────────────────────────────────────────────────────
Write-Host "$lp  Installing AI dependencies (first run only)...$rst"
python -m pip install --upgrade pip -q
python -m pip install rich -q
python -m pip install llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu -q
Write-Host "$pk  Dependencies ready.$rst"
Write-Host ""

# ── MODEL DOWNLOAD ──────────────────────────────────────────────────────────
if (-Not (Test-Path $ModelPath)) {
    Write-Host "$lp  Downloading AI model (~1.1 GB). Grab a coffee — one time only.$rst"
    Invoke-WebRequest -Uri $ModelUrl -OutFile $ModelPath
    Write-Host "$pk  Model downloaded.$rst"
} else {
    Write-Host "$lp  AI model already present. Skipping download.$rst"
}

Write-Host ""

# ── GENERATE PYTHON CHAT APP ────────────────────────────────────────────────
$safeGoal = $UserGoal -replace "'", "''"
$safeGoal = $safeGoal -replace '"', '\"'

$PythonCode = @"
import sys
from llama_cpp import Llama
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.text import Text

console = Console()

model_path = r'$ModelPath'
user_goal  = '$safeGoal'

try:
    llm = Llama(model_path=model_path, n_ctx=2048, verbose=False)
except Exception as e:
    console.print(f'[bold red]Error loading model: {e}[/bold red]')
    sys.exit(1)

system_prompt = f"""You are an elite, AI-Native Sales Operations Architect.

Your user's #1 goal right now is: {user_goal}

Keep every response grounded in that goal unless they redirect you.

Core Philosophy — embed AI into every workflow using three modes:
  • Analyze   — examine data before a human touches it
  • Recommend — propose next actions based on data
  • Automate  — eliminate repetitive manual tasks

Specialized knowledge:
  • Order Processing: validate missing fields, SKU mismatches, CPQ errors, draft order status narratives
  • Stuck Orders: flag anything sitting in one stage too long
  • Weekly Data Integrity: missing close dates, empty notes, inactive 60+ day deals, opportunities without products
  • CRM Hygiene: proactive, not reactive — catch problems upstream

Style: practical, encouraging, precise. Every answer should move them closer to reducing manual work by at least 20%.
When they describe a problem, immediately suggest how to detect or automate a fix."""

messages = [{{'role': 'system', 'content': system_prompt}}]

title = Text("✦  SalesOps AI  ✦", style="bold magenta")
subtitle = f"Focused on: [italic pink1]{user_goal}[/italic pink1]\nType your question or type [bold]exit[/bold] to quit."
console.print(Panel.fit(subtitle, title=title, border_style="magenta"))
console.print("")

while True:
    try:
        user_input = console.input('[bold magenta]You ➤ [/bold magenta] ')
        if user_input.strip().lower() in ['exit', 'quit', 'q']:
            console.print("[magenta]Goodbye. Go automate something. ✦[/magenta]")
            break
        if not user_input.strip():
            continue

        messages.append({{'role': 'user', 'content': user_input}})

        with console.status("[magenta]Thinking...[/magenta]", spinner="dots"):
            response = llm.create_chat_completion(
                messages=messages,
                max_tokens=600,
                temperature=0.7
            )

        reply = response['choices'][0]['message']['content']
        messages.append({{'role': 'assistant', 'content': reply}})

        console.print("")
        console.print("[bold magenta]SalesOps AI ✦[/bold magenta]")
        console.print(Markdown(reply))
        console.print("[magenta]──────────────────────────────────[/magenta]")
        console.print("")

    except KeyboardInterrupt:
        console.print("\n[magenta]Session ended. ✦[/magenta]")
        break
"@

Set-Content -Path $PyScript -Value $PythonCode -Encoding UTF8

# ── LAUNCH ──────────────────────────────────────────────────────────────────
Write-Host "$hp  Launching your advisor now...$rst"
Write-Host ""
python $PyScript
