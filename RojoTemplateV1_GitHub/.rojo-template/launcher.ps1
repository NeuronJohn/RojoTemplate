$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$TemplateName = "RojoTemplateV1"
$FallbackRojoVersion = "7.7.0"

$SystemDir = $PSScriptRoot
$Root = Split-Path -Parent $SystemDir
Set-Location -LiteralPath $Root

$VersionFile = Join-Path $Root "version.txt"
$ProjectFile = Join-Path $Root "default.project.json"
$SrcDir = Join-Path $Root "src"
$StateFile = Join-Path $SystemDir "STATE.json"
$BuildDir = Join-Path $Root ".build"
$ToolsDir = Join-Path $Root ".tools\rojo"
$VersionsDir = Join-Path $Root "_versions"
$DeleteManifest = Join-Path $Root "_AI_DELETE.txt"

$script:HadWarning = $false
$script:LauncherFinished = $false
$script:UserChoseStop = $false

function Show-Warning([string]$Message) {
    $script:HadWarning = $true
    Write-Warning $Message
}

function Finish-Launcher([int]$ExitCode = 0) {
    if ($script:LauncherFinished) {
        exit $ExitCode
    }

    $script:LauncherFinished = $true

    if ($script:UserChoseStop) {
        exit $ExitCode
    }

    Write-Host ""

    if ($script:HadWarning -or $ExitCode -ne 0) {
        Write-Host "============================================================" -ForegroundColor Yellow
        if ($ExitCode -eq 0) {
            Write-Host "Launcher finished with one or more warnings." -ForegroundColor Yellow
        } else {
            Write-Host "Launcher stopped with an error (exit code $ExitCode)." -ForegroundColor Red
        }
        Write-Host "Review the messages above." -ForegroundColor Yellow
        Write-Host "Press any key to close this window..." -ForegroundColor Yellow
        Write-Host "============================================================" -ForegroundColor Yellow

        try {
            [void]$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        catch {
            # Fallback for hosts where RawUI key reading is unavailable.
            cmd /c pause | Out-Null
        }
    }
    else {
        Write-Host "Launcher finished successfully. Closing in 6 seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 6
    }

    exit $ExitCode
}

trap {
    $script:HadWarning = $true
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Finish-Launcher 1
}

function Write-Step([string]$Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Continue-Anyway([string]$Reason) {
    Write-Host ""
    Show-Warning $Reason
    $answer = Read-Host "Press ENTER or type Y to continue anyway. Type N to stop"

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $true
    }

    if ($answer -match '^[Nn]') {
        $script:UserChoseStop = $true
        return $false
    }

    return ($answer -match '^[Yy]')
}

function Apply-DeleteManifest {
    if (-not (Test-Path -LiteralPath $DeleteManifest)) {
        return
    }

    Write-Step "Applying AI deletion manifest"

    if (-not (Test-Path -LiteralPath $SrcDir)) {
        throw "Cannot apply _AI_DELETE.txt because src is missing."
    }

    $srcFull = [System.IO.Path]::GetFullPath($SrcDir).TrimEnd('\','/')
    $targets = @()
    $seen = @{}

    foreach ($rawLine in (Get-Content -LiteralPath $DeleteManifest -ErrorAction Stop)) {
        $entry = ([string]$rawLine).Trim()

        if ([string]::IsNullOrWhiteSpace($entry) -or $entry.StartsWith("#")) {
            continue
        }

        if ([System.IO.Path]::IsPathRooted($entry)) {
            throw "_AI_DELETE.txt contains an absolute path, which is not allowed: $entry"
        }

        $normalized = $entry.Replace('/', '\').TrimStart('\')
        $target = [System.IO.Path]::GetFullPath((Join-Path $Root $normalized))

        if ($target.Equals($srcFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $target.StartsWith($srcFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "_AI_DELETE.txt may only delete paths inside src/: $entry"
        }

        if (-not $seen.ContainsKey($target)) {
            $seen[$target] = $true
            $targets += [pscustomobject]@{
                Entry = $entry.Replace('\','/')
                Full = $target
            }
        }
    }

    # Validate the entire manifest before deleting anything.
    foreach ($item in $targets) {
        if ($item.Entry -match '(^|/)\.\.(/|$)') {
            throw "_AI_DELETE.txt contains path traversal, which is not allowed: $($item.Entry)"
        }
    }

    foreach ($item in $targets) {
        if (Test-Path -LiteralPath $item.Full) {
            Remove-Item -LiteralPath $item.Full -Recurse -Force -ErrorAction Stop
            Write-Host "Deleted : $($item.Entry)" -ForegroundColor Green
        }
        else {
            Write-Host "Absent  : $($item.Entry)" -ForegroundColor DarkGray
        }
    }

    # Clean up empty source directories left behind by deleted/renamed files.
    Get-ChildItem -LiteralPath $SrcDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }

    Remove-Item -LiteralPath $DeleteManifest -Force -ErrorAction Stop
    Write-Host "Deletion manifest applied and consumed." -ForegroundColor Green
}

function Get-ProjectHash {
    if (-not (Test-Path -LiteralPath $ProjectFile)) {
        throw "default.project.json is missing."
    }
    if (-not (Test-Path -LiteralPath $SrcDir)) {
        throw "src is missing."
    }

    $items = @()
    $items += [pscustomobject]@{
        Relative = "default.project.json"
        Full = $ProjectFile
    }

    Get-ChildItem -LiteralPath $SrcDir -File -Recurse -Force |
        ForEach-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart('\','/').Replace('\','/')
            $items += [pscustomobject]@{
                Relative = $relative
                Full = $_.FullName
            }
        }

    $items = $items | Sort-Object Relative

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        foreach ($item in $items) {
            $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($item.Relative + [char]0)
            if ($pathBytes.Length -gt 0) {
                [void]$sha.TransformBlock($pathBytes, 0, $pathBytes.Length, $pathBytes, 0)
            }

            $content = [System.IO.File]::ReadAllBytes($item.Full)
            if ($content.Length -gt 0) {
                [void]$sha.TransformBlock($content, 0, $content.Length, $content, 0)
            }

            $separator = [byte[]](0)
            [void]$sha.TransformBlock($separator, 0, 1, $separator, 0)
        }

        [void]$sha.TransformFinalBlock([byte[]]@(), 0, 0)
        return ([System.BitConverter]::ToString($sha.Hash)).Replace("-", "")
    }
    finally {
        $sha.Dispose()
    }
}

function Get-InstalledRojo {
    if (-not (Test-Path -LiteralPath $ToolsDir)) { return $null }

    $candidates = Get-ChildItem -LiteralPath $ToolsDir -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $exe = Join-Path $_.FullName "rojo.exe"
            if (Test-Path -LiteralPath $exe) {
                [pscustomobject]@{
                    Version = $_.Name
                    Exe = $exe
                }
            }
        }

    if (-not $candidates) { return $null }

    return $candidates |
        Sort-Object @{Expression={
            try { [version]$_.Version } catch { [version]"0.0.0" }
        }} -Descending |
        Select-Object -First 1
}

function Install-Rojo([string]$Version, [string]$DownloadUrl) {
    $versionDir = Join-Path $ToolsDir $Version
    $exe = Join-Path $versionDir "rojo.exe"
    if (Test-Path -LiteralPath $exe) {
        return $exe
    }

    New-Item -ItemType Directory -Force -Path $versionDir | Out-Null
    $tempZip = Join-Path $env:TEMP ("rojo-" + [guid]::NewGuid().ToString("N") + ".zip")
    $tempExtract = Join-Path $env:TEMP ("rojo-" + [guid]::NewGuid().ToString("N"))

    try {
        Write-Host "Downloading Rojo $Version..."
        Invoke-WebRequest -UseBasicParsing -Headers @{ "User-Agent" = $TemplateName } -Uri $DownloadUrl -OutFile $tempZip
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

        $downloadedExe = Get-ChildItem -LiteralPath $tempExtract -Filter "rojo.exe" -File -Recurse |
            Select-Object -First 1
        if (-not $downloadedExe) {
            throw "Downloaded Rojo archive did not contain rojo.exe."
        }

        Copy-Item -LiteralPath $downloadedExe.FullName -Destination $exe -Force
        return $exe
    }
    finally {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-Rojo {
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

    $archEnv = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $arch = if ($archEnv -match "ARM64") { "aarch64" } else { "x86_64" }

    $latestVersion = $null
    $latestUrl = $null

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod -Headers @{ "User-Agent" = $TemplateName } -Uri "https://api.github.com/repos/rojo-rbx/rojo/releases/latest"
        $latestVersion = ([string]$release.tag_name).TrimStart("v")
        $assetName = "rojo-$latestVersion-windows-$arch.zip"
        $asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
        if ($asset) {
            $latestUrl = [string]$asset.browser_download_url
        } else {
            $latestVersion = $null
        }
    }
    catch {
        Show-Warning "Could not check GitHub for the newest Rojo release. Existing/fallback Rojo will be used."
    }

    $installed = Get-InstalledRojo
    $chosenVersion = $null
    $chosenExe = $null

    if ($latestVersion -and $latestUrl) {
        try {
            $chosenExe = Install-Rojo $latestVersion $latestUrl
            $chosenVersion = $latestVersion
        }
        catch {
            Show-Warning "Could not install newest Rojo $latestVersion`: $($_.Exception.Message)"
        }
    }

    if (-not $chosenExe -and $installed) {
        $chosenVersion = $installed.Version
        $chosenExe = $installed.Exe
        Show-Warning "Using already-installed project-local Rojo $chosenVersion."
    }

    if (-not $chosenExe) {
        $fallbackUrl = "https://github.com/rojo-rbx/rojo/releases/download/v$FallbackRojoVersion/rojo-$FallbackRojoVersion-windows-$arch.zip"
        $chosenExe = Install-Rojo $FallbackRojoVersion $fallbackUrl
        $chosenVersion = $FallbackRojoVersion
    }

    # Keep only the chosen project-local Rojo version.
    Get-ChildItem -LiteralPath $ToolsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $chosenVersion } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        Version = $chosenVersion
        Exe = $chosenExe
    }
}

function Find-Studio {
    $versionRoot = Join-Path $env:LOCALAPPDATA "Roblox\Versions"
    if (Test-Path -LiteralPath $versionRoot) {
        $studio = Get-ChildItem -LiteralPath $versionRoot -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($studio) { return $studio.FullName }
    }

    $command = Get-Command "RobloxStudioBeta.exe" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    return $null
}

function Get-StudiosUsingProjectBuild {
    $matches = @()

    try {
        $buildPrefix = ([System.IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/') + '\').ToLowerInvariant()
        $studioProcesses = Get-CimInstance Win32_Process -Filter "Name='RobloxStudioBeta.exe'" -ErrorAction Stop

        foreach ($studioProcess in $studioProcesses) {
            $commandLine = [string]$studioProcess.CommandLine
            if ([string]::IsNullOrWhiteSpace($commandLine)) {
                continue
            }

            $normalizedCommand = $commandLine.Replace('/', '\').ToLowerInvariant()
            if (-not $normalizedCommand.Contains($buildPrefix)) {
                continue
            }

            try {
                $process = Get-Process -Id ([int]$studioProcess.ProcessId) -ErrorAction Stop
                $matches += $process
            }
            catch {}
        }
    }
    catch {
        # Process command-line inspection is a convenience. Build replacement
        # still has a single-Studio fallback if CIM inspection is unavailable.
    }

    return @($matches)
}

function Focus-StudioProcess([System.Diagnostics.Process]$Process) {
    try {
        $Process.Refresh()

        try {
            $shell = New-Object -ComObject WScript.Shell
            [void]$shell.AppActivate([int]$Process.Id)
        }
        catch {}

        if ($Process.MainWindowHandle -ne 0) {
            if (-not ([System.Management.Automation.PSTypeName]'RojoTemplateNativeWindow').Type) {
                Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RojoTemplateNativeWindow {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
"@
            }

            [void][RojoTemplateNativeWindow]::ShowWindowAsync($Process.MainWindowHandle, 9)
            [void][RojoTemplateNativeWindow]::SetForegroundWindow($Process.MainWindowHandle)
        }

        return $true
    }
    catch {
        return $false
    }
}

function Wait-ForProjectStudioToClose {
    $announcedPids = @{}

    while ($true) {
        $studios = @(Get-StudiosUsingProjectBuild)
        if ($studios.Count -eq 0) {
            return
        }

        $studio = $studios | Select-Object -First 1
        if (-not $announcedPids.ContainsKey($studio.Id)) {
            Write-Host ""
            Write-Host "Roblox Studio is using this project's current .build file." -ForegroundColor Yellow
            Write-Host "Focusing that Studio window now. Close it when ready; this launcher will resume automatically." -ForegroundColor Yellow
            [void](Focus-StudioProcess $studio)
            $announcedPids[$studio.Id] = $true
        }

        Start-Sleep -Milliseconds 600
    }
}

function Install-BuildFile([string]$TempBuild, [string]$DestinationBuild) {
    Wait-ForProjectStudioToClose

    $attempt = 0
    $lastFocusedPid = -1

    while ($true) {
        try {
            Get-ChildItem -LiteralPath $BuildDir -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction Stop

            Move-Item -LiteralPath $TempBuild -Destination $DestinationBuild -Force -ErrorAction Stop
            return
        }
        catch {
            $attempt++
            $studios = @(Get-StudiosUsingProjectBuild)

            if ($studios.Count -eq 0) {
                $allStudios = @(Get-Process -Name "RobloxStudioBeta" -ErrorAction SilentlyContinue)
                if ($allStudios.Count -eq 1) {
                    $studios = $allStudios
                }
            }

            if ($studios.Count -eq 0 -or $attempt -gt 240) {
                throw "Could not replace the current .build file: $($_.Exception.Message)"
            }

            $studio = $studios | Select-Object -First 1
            if ($studio.Id -ne $lastFocusedPid) {
                Write-Host ""
                Write-Host "The current build is locked by Roblox Studio." -ForegroundColor Yellow
                Write-Host "Focusing Studio. Close that window; this launcher will keep retrying and continue automatically." -ForegroundColor Yellow
                [void](Focus-StudioProcess $studio)
                $lastFocusedPid = $studio.Id
            }

            Start-Sleep -Milliseconds 500
        }
    }
}

function Open-Studio([string]$PlaceFile) {
    $studio = Find-Studio
    if ($studio) {
        $quotedPlaceFile = '"' + $PlaceFile + '"'
        Start-Process -FilePath $studio -ArgumentList @("--task", "EditFile", "--localPlaceFile", $quotedPlaceFile)
        return
    }

    Show-Warning "Roblox Studio executable was not found in the normal install folders. Trying the .rbxl file association."
    Start-Process -FilePath $PlaceFile
}

function Write-State([string]$Version, [string]$Label, [string]$Hash, [string]$RojoVersion, [string]$BuildName) {
    $state = [ordered]@{
        template = $TemplateName
        project = $ProjectName
        version = $Version
        label = $Label
        projectHash = $Hash
        rojoVersion = $RojoVersion
        build = ".build/$BuildName"
        lastSuccessfulRunUtc = [DateTime]::UtcNow.ToString("o")
    }

    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function New-VersionBackup([string]$BackupPath, [string]$BuildFile) {
    $staging = Join-Path $env:TEMP ("rojotemplate-backup-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    try {
        $exclude = @(".git", ".tools", ".build", "_versions")
        Get-ChildItem -LiteralPath $Root -Force | Where-Object {
            $exclude -notcontains $_.Name
        } | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $staging -Recurse -Force
        }

        Copy-Item -LiteralPath $BuildFile -Destination (Join-Path $staging (Split-Path -Leaf $BuildFile)) -Force

        if (Test-Path -LiteralPath $BackupPath) {
            throw "Backup already exists: $BackupPath"
        }

        Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $BackupPath -CompressionLevel Optimal
    }
    finally {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-GitExecutable {
    # 1) Normal Git on PATH.
    $command = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $command = Get-Command "git" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    # 2) Common Git for Windows install locations.
    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Git\cmd\git.exe")
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) {
        $candidates += (Join-Path $programFilesX86 "Git\cmd\git.exe")
    }

    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    # 3) GitHub Desktop bundles Git. Find the newest installed Desktop app.
    if ($env:LOCALAPPDATA) {
        $desktopRoot = Join-Path $env:LOCALAPPDATA "GitHubDesktop"
        if (Test-Path -LiteralPath $desktopRoot) {
            $desktopApps = Get-ChildItem -LiteralPath $desktopRoot -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending

            foreach ($app in $desktopApps) {
                $desktopCandidates = @(
                    (Join-Path $app.FullName "resources\app\git\cmd\git.exe"),
                    (Join-Path $app.FullName "resources\app\git\bin\git.exe")
                )

                foreach ($candidate in $desktopCandidates) {
                    if (Test-Path -LiteralPath $candidate) {
                        return $candidate
                    }
                }
            }
        }
    }

    return $null
}

function Sync-AiBranch([string]$Label) {
    # Git writes harmless warnings to stderr. With the launcher's global
    # ErrorActionPreference=Stop, Windows PowerShell can incorrectly promote
    # those native stderr messages into terminating PowerShell errors.
    # Inside this function, rely on Git's actual exit code instead.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $git = Get-GitExecutable
    if (-not $git) {
        Write-Host "AI Sync: Git was not found; skipped." -ForegroundColor DarkGray
        return [pscustomobject]@{ Success = $false; Optional = $true; Message = "Git was not found." }
    }

    & $git -C $Root rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "AI Sync: not a Git repository yet; skipped." -ForegroundColor DarkGray
        return [pscustomobject]@{ Success = $false; Optional = $true; Message = "This folder is not a Git repository." }
    }

    $origin = & $git -C $Root remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($origin | Out-String))) {
        Write-Host "AI Sync: no Git 'origin' configured yet; skipped." -ForegroundColor DarkGray
        return [pscustomobject]@{ Success = $false; Optional = $true; Message = "No origin remote is configured." }
    }

    $tempIndex = Join-Path $env:TEMP ("rojotemplate-index-" + [guid]::NewGuid().ToString("N"))
    $oldIndex = $env:GIT_INDEX_FILE
    $oldAuthorName = $env:GIT_AUTHOR_NAME
    $oldAuthorEmail = $env:GIT_AUTHOR_EMAIL
    $oldCommitterName = $env:GIT_COMMITTER_NAME
    $oldCommitterEmail = $env:GIT_COMMITTER_EMAIL

    try {
        $env:GIT_INDEX_FILE = $tempIndex
        $env:GIT_AUTHOR_NAME = "RojoTemplate AI Sync"
        $env:GIT_AUTHOR_EMAIL = "ai-sync@local"
        $env:GIT_COMMITTER_NAME = "RojoTemplate AI Sync"
        $env:GIT_COMMITTER_EMAIL = "ai-sync@local"

        # Start from the user's current commit without touching their real Git index.
        & $git -C $Root read-tree HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            & $git -C $Root read-tree --empty 2>$null
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Could not initialize the temporary Git index."
        }

        # Stage the current working tree into the temporary index.
        # core.autocrlf=false keeps harmless LF/CRLF conversion warnings out of the launcher.
        & $git -c core.autocrlf=false -c core.safecrlf=false -C $Root add -A -- . 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not stage the current project for AI sync."
        }

        # STATE.json is intentionally gitignored on main, but ai-sync should contain it.
        if (Test-Path -LiteralPath $StateFile) {
            & $git -c core.autocrlf=false -c core.safecrlf=false -C $Root add -f -- ".rojo-template/STATE.json" 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not include STATE.json in AI sync."
            }
        }

        $tree = (& $git -C $Root write-tree 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $tree) {
            throw "Could not create the AI-sync Git tree."
        }

        # First-run safe remote lookup:
        # ls-remote returns no matching line when ai-sync does not exist yet.
        $remoteLine = (& $git -C $Root ls-remote --heads origin "refs/heads/ai-sync" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Could not contact the GitHub origin."
        }

        $parent = $null

        if ($remoteLine) {
            $remoteCommit = ($remoteLine -split '\s+')[0]

            & $git -C $Root fetch origin "refs/heads/ai-sync:refs/remotes/origin/ai-sync" --quiet 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not fetch the existing ai-sync branch."
            }

            $parent = (& $git -C $Root rev-parse "refs/remotes/origin/ai-sync" 2>$null | Out-String).Trim()
            if (-not $parent) {
                $parent = $remoteCommit
            }
        }
        else {
            # ai-sync does not exist yet. This is expected on the first run.
            $head = (& $git -C $Root rev-parse HEAD 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $head) {
                $parent = $head
            }
        }

        if ($parent) {
            $commit = (& $git -C $Root commit-tree $tree -p $parent -m "AI sync $Label" 2>$null | Out-String).Trim()
        }
        else {
            $commit = (& $git -C $Root commit-tree $tree -m "AI sync $Label" 2>$null | Out-String).Trim()
        }

        if ($LASTEXITCODE -ne 0 -or -not $commit) {
            throw "Could not create the AI-sync commit."
        }

        # Keep a local branch ref without checking it out.
        & $git -C $Root update-ref "refs/heads/ai-sync" $commit 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not update the local ai-sync branch."
        }

        # First run creates the remote branch; later runs fast-forward it.
        & $git -C $Root push -u origin "refs/heads/ai-sync:refs/heads/ai-sync" --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub rejected the ai-sync push. Check authentication/network access, then run start.bat again."
        }

        # Refresh the local remote-tracking reference quietly.
        & $git -C $Root fetch origin "refs/heads/ai-sync:refs/remotes/origin/ai-sync" --quiet 2>$null

        Write-Host "AI Sync: pushed latest local project to origin/ai-sync." -ForegroundColor Green
        return [pscustomobject]@{ Success = $true; Optional = $false; Message = "origin/ai-sync updated." }
    }
    catch {
        $message = $_.Exception.Message
        return [pscustomobject]@{ Success = $false; Optional = $false; Message = $message }
    }
    finally {
        if ($null -eq $oldIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue } else { $env:GIT_INDEX_FILE = $oldIndex }
        if ($null -eq $oldAuthorName) { Remove-Item Env:GIT_AUTHOR_NAME -ErrorAction SilentlyContinue } else { $env:GIT_AUTHOR_NAME = $oldAuthorName }
        if ($null -eq $oldAuthorEmail) { Remove-Item Env:GIT_AUTHOR_EMAIL -ErrorAction SilentlyContinue } else { $env:GIT_AUTHOR_EMAIL = $oldAuthorEmail }
        if ($null -eq $oldCommitterName) { Remove-Item Env:GIT_COMMITTER_NAME -ErrorAction SilentlyContinue } else { $env:GIT_COMMITTER_NAME = $oldCommitterName }
        if ($null -eq $oldCommitterEmail) { Remove-Item Env:GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue } else { $env:GIT_COMMITTER_EMAIL = $oldCommitterEmail }
        Remove-Item -LiteralPath $tempIndex -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

# ----- Validate project -----
Write-Step "Reading project"

if (-not (Test-Path -LiteralPath $VersionFile)) { throw "version.txt is missing." }
if (-not (Test-Path -LiteralPath $ProjectFile)) { throw "default.project.json is missing." }
if (-not (Test-Path -LiteralPath $SrcDir)) { throw "src is missing." }

Apply-DeleteManifest

$ProjectName = Split-Path -Leaf $Root
$Version = (Get-Content -LiteralPath $VersionFile -Raw).Trim()

if ($Version -notmatch '^\d+\.\d+\.\d+_[A-Za-z0-9-]+$') {
    throw "version.txt must contain exactly one value like: 0.0.0_Foundation"
}

$Label = "${ProjectName}_V${Version}"
$BuildName = "$Label.rbxl"
$BuildFile = Join-Path $BuildDir $BuildName
$BackupFile = Join-Path $VersionsDir "$Label.zip"
$ProjectHash = Get-ProjectHash

Write-Host "Project : $ProjectName"
Write-Host "Version : $Version"
Write-Host "Hash    : $($ProjectHash.Substring(0, 12))..."

# ----- Immutable version protection -----
$VersionConflict = $false
$ExistingState = $null
if (Test-Path -LiteralPath $StateFile) {
    try { $ExistingState = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json } catch {}
}

if ($ExistingState -and $ExistingState.version -eq $Version -and $ExistingState.projectHash -ne $ProjectHash) {
    $VersionConflict = $true
    $message = "Project files changed but version.txt is still '$Version'. The existing version backup will NOT be overwritten. Bump version.txt on the next update."
    if (-not (Continue-Anyway $message)) { Finish-Launcher 2 }
}

# ----- Rojo -----
Write-Step "Checking Rojo"
try {
    $Rojo = Get-Rojo
    Write-Host "Rojo   : $($Rojo.Version)"
}
catch {
    if (Test-Path -LiteralPath $BuildFile) {
        if (Continue-Anyway "Rojo is unavailable, but the current build exists. Open the existing build instead?") {
            Open-Studio $BuildFile
            Finish-Launcher 0
        }
    }
    throw
}

# ----- Build safely to temp -----
Write-Step "Building $BuildName"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $VersionsDir | Out-Null

$TempBuild = Join-Path $env:TEMP ("rojotemplate-build-" + [guid]::NewGuid().ToString("N") + ".rbxl")
try {
    & $Rojo.Exe build $ProjectFile -o $TempBuild
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $TempBuild)) {
        throw "Rojo build failed."
    }

    # .build contains only the current rbxl after a successful build.
    # If Studio has the previous build open, focus it and wait rather than
    # forcing the user to restart this launcher.
    Install-BuildFile $TempBuild $BuildFile
}
catch {
    Remove-Item -LiteralPath $TempBuild -Force -ErrorAction SilentlyContinue

    $existingBuild = Get-ChildItem -LiteralPath $BuildDir -Filter "*.rbxl" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($existingBuild -and (Continue-Anyway "New build failed, but an existing .rbxl is available. Open that existing build instead?")) {
        Open-Studio $existingBuild.FullName
        Finish-Launcher 0
    }
    throw
}

# ----- State + immutable ZIP backup -----
if (-not $VersionConflict) {
    Write-State $Version $Label $ProjectHash $Rojo.Version $BuildName

    if (-not (Test-Path -LiteralPath $BackupFile)) {
        Write-Step "Creating immutable version backup"
        try {
            New-VersionBackup $BackupFile $BuildFile
            Write-Host "Backup : _versions\$Label.zip" -ForegroundColor Green
        }
        catch {
            if (-not (Continue-Anyway "Backup ZIP could not be created: $($_.Exception.Message)")) {
                Finish-Launcher 3
            }
        }
    } else {
        Write-Host "Backup : already exists; left untouched." -ForegroundColor DarkGray
    }
} else {
    Show-Warning "STATE.json and the existing version backup were left untouched because the version was not bumped."
}

# ----- AI sync is optional and never blocks Roblox -----
Write-Step "AI sync"
$AiSyncResult = Sync-AiBranch $Label

if (-not $AiSyncResult.Success -and -not $AiSyncResult.Optional) {
    if (-not (Continue-Anyway "AI Sync failed: $($AiSyncResult.Message)`nThe Roblox project is built and still works. Continue to Studio?")) {
        Finish-Launcher 4
    }
}

# ----- Launch Studio and exit -----
Write-Step "Opening Roblox Studio"
try {
    Open-Studio $BuildFile
    Write-Host "Studio launched." -ForegroundColor Green
    Finish-Launcher 0
}
catch {
    if (Continue-Anyway "Automatic Studio launch failed. You can still open '$BuildFile' manually.") {
        Finish-Launcher 0
    }
    throw
}
