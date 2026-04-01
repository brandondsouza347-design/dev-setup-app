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
    $entry = "[$(Get-Date -Format 'HH:mm:ss.fff')] $Msg"
    # Retry up to 15 times with 1s gaps (15s max) — AV scanners (Defender)
    # hold the log file open briefly after every write on corporate machines.
    for ($wl = 1; $wl -le 15; $wl++) {
        try {
            $entry | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8 -ErrorAction Stop
            break
        } catch {
            if ($wl -lt 15) { Start-Sleep -Milliseconds 1000 }
        }
    }
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
        # Settle delay: give the previous step's file handles (log, staged script)
        # time to fully release before we open the agent.log for writing.
        Start-Sleep -Milliseconds 1500

        # ── Atomically claim the cmd file ─────────────────────────────────────
        # Rename cmd_*.json → processing_*.json BEFORE doing any work.
        # This prevents the outer while loop from picking up the same file again
        # if Remove-Item at the end fails (e.g. AV scanner holds it open).
        $processingFile = "$DIR\processing_$($f.BaseName -replace '^cmd_','')"
        try {
            Move-Item -LiteralPath $f.FullName -Destination $processingFile -Force -ErrorAction Stop
        } catch {
            Write-Log "Could not claim cmd file $($f.Name) ($_) — skipping to avoid double-execution"
            continue
        }

        $raw  = Get-Content -LiteralPath $processingFile -Raw -Encoding UTF8
        $cmd  = $raw | ConvertFrom-Json
        $stepId   = $cmd.step_id
        $script   = $cmd.script
        $runId    = if ($cmd.run_id) { $cmd.run_id } else { '' }
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

            # Kill any leftover powershell.exe that is still holding this step's script file.
            # This is the primary cause of "file in use by another process" on retry —
            # the child process from the previous attempt hasn't fully exited yet.
            try {
                $staleProcs = Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.CommandLine -like "*step_$stepId*" }
                foreach ($proc in $staleProcs) {
                    Write-Log "Killing stale powershell.exe (PID $($proc.ProcessId)) holding step_$stepId.ps1"
                    Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
                }
                # Wait long enough for the killed process to release all file handles
                # before we attempt to overwrite the staged script.
                if ($staleProcs) { Start-Sleep -Seconds 3 }
            } catch {
                Write-Log "Warning: could not query for stale processes: $_"
            }

            # Remove any stale staged file from a previous run before writing.
            Remove-Item -Path $trustedScript -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300

            # Retry the stage write a few times in case the file handle is still releasing
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    Get-Content -LiteralPath $script -Encoding UTF8 -Raw |
                        Set-Content -LiteralPath $trustedScript -Encoding UTF8
                    break
                } catch {
                    if ($attempt -lt 5) {
                        Write-Log "Stage attempt $attempt failed ($_) — retrying in 1s..."
                        Start-Sleep -Seconds 1
                    } else {
                        throw
                    }
                }
            }
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
            # Retry removal with generous delays — child powershell.exe may hold
            # the file open briefly after exit (Windows file handle release is async).
            # 30 attempts × 500ms = up to 15s wait before giving up.
            $removed = $false
            for ($r = 1; $r -le 30; $r++) {
                try {
                    Remove-Item -Path "$PROG_DIR\step_$stepId.ps1" -Force -ErrorAction Stop
                    $removed = $true
                    break
                } catch {
                    Start-Sleep -Milliseconds 500
                }
            }
            if (-not $removed) {
                Write-Log "Warning: could not remove staged script step_$stepId.ps1 — will be overwritten on next run"
            }
        }

        # Write completion signal with retry — AV scanner can hold the done file
        # open briefly, causing Out-File to fail on some corporate machines.
        # Include run_id so Rust can reject stale done files from previous attempts.
        $doneContent = "{`"done`":true,`"code`":$exitCode,`"run_id`":`"$runId`"}"
        for ($dw = 1; $dw -le 15; $dw++) {
            try {
                $doneContent | Out-File -FilePath $doneFile -Encoding ASCII -Force -ErrorAction Stop
                break
            } catch {
                if ($dw -lt 15) { Start-Sleep -Milliseconds 1000 }
            }
        }
        Write-Log "Step '$stepId' finished (exit code $exitCode)"
        Remove-Item -LiteralPath $processingFile -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 500
}

Write-Log "Agent exiting normally"
