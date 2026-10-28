# One-command reproduction on Windows (Docker Desktop):
#   powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1            # make all
#   powershell -ExecutionPolicy Bypass -File scripts\run_all.ps1 sim        # one target
# Runs every step inside the pinned iic-osic-tools container.
param([string]$Target = "all")
$ErrorActionPreference = "Stop"
$Image = "hpretl/iic-osic-tools:2026.10"
$Repo = (Resolve-Path "$PSScriptRoot\..").Path
docker run --rm -v "${Repo}:/foss/designs/pwm3" -w /foss/designs/pwm3 $Image --skip make $Target
exit $LASTEXITCODE
