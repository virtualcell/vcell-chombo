# Run a command, retrying a bounded number of times:
#
#   pwsh .github/scripts/Retry.ps1 <attempts> <delay-seconds> <cmd> [args...]
#
# The PowerShell counterpart of retry.sh, for the Windows jobs. See that file
# for why this exists -- gnu-config fetches its sources from GNU Savannah, which
# returned HTTP 500 nine times in one day, and a `conan install` that builds
# from source cannot avoid it.
#
# Bounded on purpose: a reproducible failure still fails the job, and every
# attempt is announced so the log says whether something was retried.

Set-StrictMode -Version Latest

$attempts = [int]$args[0]
$delay    = [int]$args[1]
$command  = $args[2]
$rest     = @()
if ($args.Count -gt 3) { $rest = $args[3..($args.Count - 1)] }

if (-not $command) { Write-Host "Retry.ps1: no command given"; exit 2 }

for ($i = 1; $i -le $attempts; $i++) {
    if ($i -gt 1) { Write-Host "::warning::Retry.ps1: attempt $i of $attempts for: $command $rest" }
    & $command @rest
    $status = $LASTEXITCODE
    if ($status -eq 0) {
        if ($i -gt 1) { Write-Host "Retry.ps1: succeeded on attempt $i" }
        exit 0
    }
    Write-Host "Retry.ps1: attempt $i of $attempts failed with status $status"
    if ($i -lt $attempts) { Start-Sleep -Seconds $delay }
}

Write-Host "::error::Retry.ps1: all $attempts attempts failed for: $command $rest"
exit $status
