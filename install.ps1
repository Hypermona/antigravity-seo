# SEO Skills Installer for Windows (Google Antigravity & Claude Code)
# PowerShell installation script

param(
    [ValidateSet('Antigravity', 'Claude', 'All')]
    [string]$Target = 'Antigravity',
    [ValidateSet('Global', 'Workspace')]
    [string]$Scope = 'Global'
)

if ($env:CLAUDE_SEO_TARGET) {
    $Target = $env:CLAUDE_SEO_TARGET
}

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "|   SEO Skills - Installer             |" -ForegroundColor Cyan
Write-Host "|   Target: $Target" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Supported range. scripts/runtime.py (MIN_PYTHON, MAX_PYTHON) is the source
# of truth; tests/test_python_range.py keeps this copy in step.
$MinMinor = 11
$MaxMinor = 14
$script:SeenPython = @()

function Resolve-Python {
    # An override must be supported; it is never silently replaced.
    if ($env:CLAUDE_SEO_PYTHON) {
        return Test-PythonCandidate -Exe $env:CLAUDE_SEO_PYTHON -Args @()
    }

    # The default interpreter first, so an existing runtime keeps its Python.
    # 'py -3' means the newest installed, which can be one we do not support yet.
    $candidates = @(
        @{ Exe = 'py'; Args = @('-3') },
        @{ Exe = 'python3'; Args = @() },
        @{ Exe = 'python'; Args = @() }
    )
    for ($minor = $MaxMinor; $minor -ge $MinMinor; $minor--) {
        $candidates += @{ Exe = 'py'; Args = @("-3.$minor") }
        $candidates += @{ Exe = "python3.$minor"; Args = @() }
    }

    foreach ($candidate in $candidates) {
        $resolved = Test-PythonCandidate -Exe $candidate.Exe -Args $candidate.Args
        if ($null -ne $resolved) {
            return $resolved
        }
    }

    return $null
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Args,
        [switch]$Quiet
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $hasNativePreference = $null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($hasNativePreference) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & $Exe @Args 2>&1 | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }

    if (-not $Quiet -and $null -ne $output -and $output.Count -gt 0) {
        $output | ForEach-Object { Write-Host $_ }
    }

    return @{ ExitCode = $exitCode; Output = $output }
}

function Test-PythonCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$Args = @()
    )

    $pythonCmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if ($null -eq $pythonCmd) {
        return $null
    }

    $probeCode = "import sys; print(sys.executable); print(sys.version.split()[0]); raise SystemExit(0 if (3, $MinMinor) <= sys.version_info[:2] <= (3, $MaxMinor) else 1)"
    $probe = Invoke-External -Exe $Exe -Args @($Args + @('-c', $probeCode)) -Quiet
    $probeText = ($probe.Output -join "`n")

    if ($probeText -match 'Microsoft Store|WindowsApps|App execution alias|was not found') {
        return $null
    }

    if ($probe.ExitCode -ne 0) {
        if ($probe.ExitCode -eq 1 -and $probe.Output.Count -ge 2 -and "$($probe.Output[1])" -match '^\d+\.\d+') {
            $script:SeenPython += "$($probe.Output[1]) ($(@($Exe) + $Args -join ' '))"
        }
        return $null
    }

    return @{ Exe = $Exe; Args = $Args }
}

# Check prerequisites
$python = Resolve-Python
if ($null -eq $python) {
    $found = 'no Python'
    if ($script:SeenPython.Count -gt 0) { $found = $script:SeenPython -join ', ' }
    if ($env:CLAUDE_SEO_PYTHON) {
        Write-Host "[x] CLAUDE_SEO_PYTHON must be Python 3.$MinMinor to 3.$MaxMinor. Found: $found." -ForegroundColor Red
    } else {
        Write-Host "[x] Claude SEO needs Python 3.$MinMinor to 3.$MaxMinor. Found: $found. Install Python 3.$MaxMinor from python.org or set CLAUDE_SEO_PYTHON." -ForegroundColor Red
    }
    exit 1
}

try {
    $pythonVersion = & $python.Exe @($python.Args + @('--version')) 2>&1
    Write-Host "[+] $pythonVersion detected" -ForegroundColor Green
} catch {
    Write-Host "[x] Python is installed but could not be executed." -ForegroundColor Red
    exit 1
}

try {
    git --version | Out-Null
    Write-Host "[+] Git detected" -ForegroundColor Green
} catch {
    Write-Host "[x] Git is required but not installed." -ForegroundColor Red
    exit 1
}

# Set paths
$SkillsBase = if ($Target -eq 'Claude') {
    if ($Scope -eq 'Workspace') { ".\.claude\skills" } else { "$env:USERPROFILE\.claude\skills" }
} else {
    if ($Scope -eq 'Workspace') { ".\.agents\skills" } else { "$env:USERPROFILE\.agents\skills" }
}
$SkillDir = "$SkillsBase\seo"
$AgentDir = if ($Target -eq 'Claude') {
    if ($Scope -eq 'Workspace') { ".\.claude\agents" } else { "$env:USERPROFILE\.claude\agents" }
} else {
    if ($Scope -eq 'Workspace') { ".\.agents\agents" } else { "$env:USERPROFILE\.agents\agents" }
}
$RepoUrl = "https://github.com/AgriciDaniel/claude-seo"
# Pin to a specific release tag to prevent silent updates from main.
# This default MUST be bumped on every release. CI guard
# (tests/test_manifest_consistency.py) enforces this matches plugin.json.
# Override: $env:CLAUDE_SEO_TAG = 'main'; .\install.ps1
$RepoTag = if ($env:CLAUDE_SEO_TAG) { $env:CLAUDE_SEO_TAG } else { 'v2.6.0' }

# Create directories
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
New-Item -ItemType Directory -Force -Path $AgentDir | Out-Null

# Clone to temp directory
$TempDir = Join-Path $env:TEMP "claude-seo-install"
if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
}

$keepTemp = ($env:CLAUDE_SEO_KEEP_TEMP -eq '1')

try {
    Write-Host ">> Downloading Claude SEO ($RepoTag)..." -ForegroundColor Yellow
    $clone = Invoke-External -Exe 'git' -Args @('clone','--depth','1','--branch',$RepoTag,$RepoUrl,$TempDir) -Quiet
    if ($clone.ExitCode -ne 0) {
        throw "git clone failed. Output:`n$($clone.Output -join "`n")"
    }

    # Copy skill files
    Write-Host "=> Installing skill files..." -ForegroundColor Yellow
    $skillSource = Join-Path $TempDir 'skills\seo'
    if (-not (Test-Path $skillSource)) {
        throw "Could not find skill source folder in repo clone."
    }
    Copy-Item -Recurse -Force (Join-Path $skillSource '*') $SkillDir

    # Copy sub-skills
    $SkillsPath = "$TempDir\skills"
    if (Test-Path $SkillsPath) {
        Get-ChildItem -Directory $SkillsPath | ForEach-Object {
            $destDir = "$SkillsBase\$($_.Name)"
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item -Recurse -Force "$($_.FullName)\*" $destDir
        }
    }

    # Copy schema templates
    $SchemaPath = "$TempDir\schema"
    if (Test-Path $SchemaPath) {
        $SkillSchema = "$SkillDir\schema"
        New-Item -ItemType Directory -Force -Path $SkillSchema | Out-Null
        Copy-Item -Recurse -Force "$SchemaPath\*" $SkillSchema
    }

    # Copy deterministic data files consumed by bundled scripts such as
    # seo_updates.py. Keep the repository-relative data\ layout intact.
    $DataPath = "$TempDir\data"
    if (Test-Path $DataPath) {
        $SkillData = "$SkillDir\data"
        New-Item -ItemType Directory -Force -Path $SkillData | Out-Null
        Copy-Item -Recurse -Force "$DataPath\*" $SkillData
    }

    # Copy reference docs
    $PdfPath = "$TempDir\pdf"
    if (Test-Path $PdfPath) {
        $SkillPdf = "$SkillDir\pdf"
        New-Item -ItemType Directory -Force -Path $SkillPdf | Out-Null
        Copy-Item -Recurse -Force "$PdfPath\*" $SkillPdf
    }

    # Copy agents
    Write-Host "=> Installing subagents..." -ForegroundColor Yellow
    $AgentsPath = Join-Path $TempDir 'agents'
    if (Test-Path $AgentsPath) {
        Copy-Item -Force (Join-Path $AgentsPath '*.md') $AgentDir -ErrorAction SilentlyContinue
    }

    # Copy shared scripts
    $ScriptsPath = "$TempDir\scripts"
    if (Test-Path $ScriptsPath) {
        $SkillScripts = "$SkillDir\scripts"
        New-Item -ItemType Directory -Force -Path $SkillScripts | Out-Null
        Copy-Item -Recurse -Force "$ScriptsPath\*" $SkillScripts
    }

    # Copy the stable launcher used by skill and agent instructions. It ships in
    # scripts/ (never a top-level bin/, which hosted marketplaces reject) and
    # resolves runtime.py as a sibling, so it lands beside the copied scripts.
    $LauncherSource = Join-Path $ScriptsPath 'claude-seo'
    $SkillLauncherDir = Join-Path $SkillDir 'scripts'
    if (Test-Path $LauncherSource) {
        New-Item -ItemType Directory -Force -Path $SkillLauncherDir | Out-Null
        Copy-Item -Force $LauncherSource (Join-Path $SkillLauncherDir 'claude-seo')
    }

    # Copy hooks
    Write-Host "  Note: hook enforcement requires plugin install; manual hook copy is best-effort." -ForegroundColor Yellow
    $HooksPath = "$TempDir\hooks"
    if (Test-Path $HooksPath) {
        $SkillHooks = "$SkillDir\hooks"
        New-Item -ItemType Directory -Force -Path $SkillHooks | Out-Null
        Copy-Item -Recurse -Force "$HooksPath\*" $SkillHooks
    }

    # Copy extensions (optional add-ons: dataforseo, banana)
    $ExtensionsPath = Join-Path $TempDir 'extensions'
    if (Test-Path $ExtensionsPath) {
        Write-Host "=> Installing extensions..." -ForegroundColor Yellow
        Get-ChildItem -Directory $ExtensionsPath | ForEach-Object {
            $extName = $_.Name
            $extDir = $_.FullName
            # Extension skills
            $extSkills = Join-Path $extDir 'skills'
            if (Test-Path $extSkills) {
                Get-ChildItem -Directory $extSkills | ForEach-Object {
                    $destDir = "$SkillsBase\$($_.Name)"
                    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    Copy-Item -Recurse -Force "$($_.FullName)\*" $destDir
                }
            }
            # Extension agents
            $extAgents = Join-Path $extDir 'agents'
            if (Test-Path $extAgents) {
                Copy-Item -Force (Join-Path $extAgents '*.md') $AgentDir -ErrorAction SilentlyContinue
            }
            # Extension references
            $extRefs = Join-Path $extDir 'references'
            if (Test-Path $extRefs) {
                $refTarget = "$SkillDir\extensions\$extName\references"
                New-Item -ItemType Directory -Force -Path $refTarget | Out-Null
                Copy-Item -Recurse -Force "$extRefs\*" $refTarget
            }
            # Extension scripts
            $extScripts = Join-Path $extDir 'scripts'
            if (Test-Path $extScripts) {
                $scriptTarget = "$SkillDir\extensions\$extName\scripts"
                New-Item -ItemType Directory -Force -Path $scriptTarget | Out-Null
                Copy-Item -Recurse -Force "$extScripts\*" $scriptTarget
            }
        }
    }

    # Copy requirements.txt to skill dir for retry
    $reqFile = Join-Path $TempDir 'requirements.txt'
    $installedReqFile = Join-Path $SkillDir 'requirements.txt'
    if (Test-Path $reqFile) {
        Copy-Item -Force $reqFile $installedReqFile
    }
    $pluginManifest = Join-Path $TempDir '.claude-plugin\plugin.json'
    if (Test-Path $pluginManifest) {
        Copy-Item -Force $pluginManifest (Join-Path $SkillDir 'runtime-plugin.json')
    }

    # Manual installs have no ${CLAUDE_PLUGIN_ROOT}. Rewrite the canonical
    # launcher token in installed Markdown to the absolute installed path.
    # Claude Code's Bash tool expands $HOME on Windows as well as Unix. The
    # replacement consumes the plugin-root token, so a second pass is a no-op.
    $pluginRunner = '"${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo" run'
    $manualRunner = if ($Target -eq 'Claude') {
        '"$HOME/.claude/skills/seo/scripts/claude-seo" run'
    } else {
        '"$HOME/.agents/skills/seo/scripts/claude-seo" run'
    }
    $installedDocs = @()
    Get-ChildItem -Path $SkillsPath -Directory | ForEach-Object {
        $sourceRoot = $_.FullName
        $targetRoot = "$SkillsBase\$($_.Name)"
        $installedDocs += Get-ChildItem -Path $sourceRoot -Recurse -File -Filter '*.md' | ForEach-Object {
            $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\','/')
            Get-Item (Join-Path $targetRoot $relative) -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -Path $ExtensionsPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $extName = $_.Name
        $extSkills = Join-Path $_.FullName 'skills'
        Get-ChildItem -Path $extSkills -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $sourceRoot = $_.FullName
            $targetRoot = "$SkillsBase\$($_.Name)"
            $installedDocs += Get-ChildItem -Path $sourceRoot -Recurse -File -Filter '*.md' | ForEach-Object {
                $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\','/')
                Get-Item (Join-Path $targetRoot $relative) -ErrorAction SilentlyContinue
            }
        }
        $extRefs = Join-Path $_.FullName 'references'
        if (Test-Path $extRefs) {
            $targetRefs = Join-Path $SkillDir "extensions\$extName\references"
            $installedDocs += Get-ChildItem -Path $extRefs -Recurse -File -Filter '*.md' | ForEach-Object {
                $relative = $_.FullName.Substring($extRefs.Length).TrimStart('\','/')
                Get-Item (Join-Path $targetRefs $relative) -ErrorAction SilentlyContinue
            }
        }
    }
    $agentSources = @()
    $agentSources += Get-ChildItem -Path $AgentsPath -File -Filter '*.md' -ErrorAction SilentlyContinue
    $agentSources += Get-ChildItem -Path $ExtensionsPath -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'agents' }
    $installedDocs += $agentSources | ForEach-Object {
        Get-Item (Join-Path $AgentDir $_.Name) -ErrorAction SilentlyContinue
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $installedDocs | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        $pluginSetup = '"${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo" setup'
        $pluginDoctor = '"${CLAUDE_PLUGIN_ROOT}/scripts/claude-seo" doctor'
        $manualSetup = if ($Target -eq 'Claude') {
            '"$HOME/.claude/skills/seo/scripts/claude-seo" setup'
        } else {
            '"$HOME/.agents/skills/seo/scripts/claude-seo" setup'
        }
        $manualDoctor = if ($Target -eq 'Claude') {
            '"$HOME/.claude/skills/seo/scripts/claude-seo" doctor'
        } else {
            '"$HOME/.agents/skills/seo/scripts/claude-seo" doctor'
        }
        $updated = $text.Replace($pluginRunner, $manualRunner)
        $updated = $updated.Replace($pluginSetup, $manualSetup)
        $updated = $updated.Replace($pluginDoctor, $manualDoctor)
        $targetSkillsRel = if ($Target -eq 'Claude') { '/.claude/skills/' } else { '/.agents/skills/' }
        # Read-tool paths need the absolute skills directory, not a variable.
        $updated = $updated.Replace('${CLAUDE_PLUGIN_ROOT}/skills/', (($env:USERPROFILE -replace '\\', '/') + $targetSkillsRel))
        if ($updated -ne $text) {
            [System.IO.File]::WriteAllText($_.FullName, $updated, $utf8NoBom)
        }
    }

    # Use the same standard-library runtime on Windows. It creates an isolated
    # .venv with Scripts\python.exe and installs Chromium through that interpreter.
    Write-Host "=> Creating isolated Python runtime..." -ForegroundColor Yellow
    $runtimeScript = Join-Path $SkillDir 'scripts\runtime.py'
    $runtime = Invoke-External -Exe $python.Exe -Args @($python.Args + @($runtimeScript,'setup'))
    if ($runtime.ExitCode -ne 0 -and $runtime.ExitCode -ne 10) {
        throw "Core Python runtime setup failed. Installation is incomplete."
    }
    if ($runtime.ExitCode -eq 10) {
        Write-Host "  [!] Core runtime installed, but Chromium setup is incomplete." -ForegroundColor Yellow
    }

    # For Antigravity: register ~/.agents/skills in ~/.gemini/config/skills.json if config dir exists
    if ($Target -ne 'Claude') {
        $geminiConfigDir = "$env:USERPROFILE\.gemini\config"
        if (Test-Path $geminiConfigDir) {
            $skillsJsonPath = Join-Path $geminiConfigDir 'skills.json'
            $configData = @{ entries = @() }
            if (Test-Path $skillsJsonPath) {
                try {
                    $configData = Get-Content -Raw $skillsJsonPath | ConvertFrom-Json
                } catch {}
            }
            $existingPaths = @($configData.entries | ForEach-Object { $_.path })
            if ($existingPaths -notcontains '~/.agents/skills') {
                $configData.entries += @{ path = '~/.agents/skills' }
                $configData | ConvertTo-Json -Depth 5 | Set-Content -Path $skillsJsonPath -Encoding utf8
            }
        }
    }
} catch {
    Write-Host ""
    Write-Host "[x] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($keepTemp -and (Test-Path $TempDir)) {
        Write-Host "Temp dir kept at: $TempDir" -ForegroundColor Yellow
    }
    throw
} finally {
    if (-not $keepTemp -and (Test-Path $TempDir)) {
        Remove-Item -Recurse -Force $TempDir
    }
}

Write-Host ""
Write-Host "[+] SEO skills installed successfully for $Target!" -ForegroundColor Green
Write-Host ""
if ($Target -ne 'Claude') {
    Write-Host "Google Antigravity Usage:" -ForegroundColor Cyan
    Write-Host "  1. Start Antigravity: agy (or open Antigravity IDE / Desktop)"
    Write-Host "  2. Skills are automatically discovered in ~/.agents/skills"
    Write-Host "  3. Use slash commands or prompts in chat:"
    Write-Host "     - /seo audit https://example.com"
    Write-Host "     - /seo technical https://example.com"
    Write-Host ""
}
if ($Target -ne 'Antigravity') {
    Write-Host "Claude Code Usage:" -ForegroundColor Cyan
    Write-Host "  1. Start Claude Code:  claude"
    Write-Host "  2. Run commands:       /seo audit https://example.com"
    Write-Host ""
}
Write-Host "Python deps location: $installedReqFile" -ForegroundColor Gray
