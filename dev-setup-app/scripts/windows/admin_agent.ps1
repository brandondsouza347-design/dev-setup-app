# admin_agent.ps1 — Elevated file-based IPC agent for the Dev Setup app.
#
# ARCHITECTURE — file-based IPC (no named pipes, no .NET types):
#   All operations use only basic PowerShell cmdlets so the script works
#   correctly even when PowerShell Constrained Language Mode (CLM) is
#   enforced by a corporate WDAC/AppLocker policy.
#
# IPC directory: C:\Users\Public\DevSetupAgent\
#
#   Rust (non-elevated) writes:
#       cmd_{step_id}.json   -> {"step_id":"...","script":"C:\\...","env":{...}}
#       agent_shutdown.flag  -> signals agent to exit
#
#   This script (elevated) writes:
#       agent.log            -> running log for diagnostics
#       agent_ready.flag     -> written once on startup so Rust knows we are alive
#       log_{step_id}.txt    -> growing output log for the running step
#       done_{step_id}.json  -> {"done":true,"code":0} written when step completes
#
#Requires -RunAsAdministrator

$DIR           = "C:\Users\Public\DevSetupAgent"
$LOG_FILE      = "$DIR\agent.log"
$READY_FLAG    = "$DIR\agent_ready.flag"
$SHUTDOWN_FLAG = "$DIR\agent_shutdown.flag"

# Proof-of-life log — first thing written so we can confirm the script body ran.
"[STARTUP] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')  User=$env:USERNAME  PS=$($PSVersionTable.PSVersion)" |
    Out-File -FilePath $LOG_FILE -Encoding UTF8 -Force

function Write-Log {
    param([string]$Msg)
    "[$(Get-Date -Format 'HH:mm:ss.fff')] $Msg" | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

Write-Log "Script running from: $PSCommandPath"

# Remove stale flags from any previous run
Remove-Item -Path $READY_FLAG    -Force -ErrorAction SilentlyContinue
Remove-Item -Path $SHUTDOWN_FLAG -Force -ErrorAction SilentlyContinue

# Signal ready — Rust polls for this file
"ready" | Out-File -FilePath $READY_FLAG -Encoding UTF8 -Force
Write-Log "agent_ready.flag written — waiting for commands"

# Main loop — polls every 500ms for command files
while ($true) {
    if (Test-Path $SHUTDOWN_FLAG) {
        Write-Log "Shutdown flag detected — exiting"
        break
    }

    $cmdFiles = Get-ChildItem -Path $DIR -Filter "cmd_*.json" -ErrorAction SilentlyContinue
    foreach ($f in $cmdFiles) {
        $raw  = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        $cmd  = $raw | ConvertFrom-Json
        $stepId   = $cmd.step_id
        $script   = $cmd.script
        $stepLog  = "$DIR\log_$stepId.txt"
        $doneFile = "$DIR\done_$stepId.json"

        Write-Log "Executing step '$stepId': $script"
        "=== Step: $stepId  $(Get-Date -Format 'HH:mm:ss.fff') ===" |
            Out-File -FilePath $stepLog -Encoding UTF8 -Force

        # Apply env vars for this step (Set-Item works in CLM)
        if ($cmd.env) {
            $cmd.env.PSObject.Properties | ForEach-Object {
                Set-Item -Path "ENV:$($_.Name)" -Value $_.Value -ErrorAction SilentlyContinue
            }
        }

        $exitCode = 0
        try {
            # Stage the step script to C:\Program Files\DevSetupAgent\ before running it.
            # WDAC/AppLocker enforces Restricted Language Mode on scripts from user-writable
            # paths (AppData\Local, %TEMP%, etc.). Program Files is always trusted.
            #
            # ENCODING FIX: enable_wsl.ps1 and other step scripts are saved UTF-8 WITHOUT
            # BOM (standard on Linux/macOS editors). Windows PowerShell 5.x reads -File
            # scripts using the SYSTEM DEFAULT encoding (Windows-1252 on most corporate
            # machines) when no BOM is present. UTF-8 byte sequences for Unicode chars
            # such as (U+2713 = E2 9C 93) get misread as Windows-1252 characters,
            # corrupting string literals and causing cascading parse errors.
            #
            # Fix: read as UTF-8, write back WITH BOM. PowerShell 5.x Set-Content
            # -Encoding UTF8 always writes the UTF-8 BOM (EF BB BF), so the child
            # powershell.exe will correctly identify the file as UTF-8.
            $PROG_DIR      = "C:\Program Files\DevSetupAgent"
            $trustedScript = "$PROG_DIR\step_$stepId.ps1"
            New-Item -ItemType Directory -Force -Path $PROG_DIR | Out-Null
            Get-Content -LiteralPath $script -Encoding UTF8 -Raw |
                Set-Content -LiteralPath $trustedScript -Encoding UTF8
            Write-Log "Staged (UTF-8 BOM) step script to: $trustedScript"

            & powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass `
                -WindowStyle Hidden -File $trustedScript *>&1 |
                ForEach-Object {
                    "$_" | Out-File -FilePath $stepLog -Append -Encoding UTF8
                }
            if ($null -ne $LASTEXITCODE) { $exitCode = $LASTEXITCODE }
        } catch {
            "ERROR: $_" | Out-File -FilePath $stepLog -Append -Encoding UTF8
            $exitCode = 1
        } finally {
            # Clean up the staged copy
            Remove-Item -Path "$PROG_DIR\step_$stepId.ps1" -Force -ErrorAction SilentlyContinue
        }

        # Write completion signal then remove the command file
        "{`"done`":true,`"code`":$exitCode}" | Out-File -FilePath $doneFile -Encoding UTF8 -Force
        Write-Log "Step '$stepId' finished (exit code $exitCode)"
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 500
}

Write-Log "Agent exiting normally"
