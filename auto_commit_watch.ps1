$repoRoot = $PSScriptRoot

Write-Host "Auto-commit watcher started in $repoRoot"

while ($true) {
    try {
        $status = git -C $repoRoot status --porcelain
        if ($status) {
            git -C $repoRoot add -A
            git -C $repoRoot commit -m "Auto-commit: workspace update" --no-verify | Out-Null
            Write-Host "Committed repo changes at $(Get-Date -Format o)"
        }
    }
    catch {
        Write-Host "Auto-commit failed: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 5
}
