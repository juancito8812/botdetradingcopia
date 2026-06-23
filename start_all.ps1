# Requires PowerShell 5.1+
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WatchdogOwnerLockStream = $null
$script:WatchdogOwnerName = $null
$script:WatchdogOwnerAcquiredAt = $null
Set-Location $script:RepoRoot


function Write-Info { param([string]$m) Write-Host "[start_all] $m" }
function Write-WarnMessage { param([string]$m) Write-Host "[start_all][warn] $m" }
function Throw-StartAllError { param([string]$m) throw "[start_all][error] $m" }

# Busqueda segura de propiedades: bajo `Set-StrictMode -Version Latest`, reading a
# una propiedad inexistente en PSCustomObject lanza excepcion. Esto devuelve $null en su lugar
# para que los llamadores puedan usar guardas `$null -ne` en objetos derivados de JSON.
function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $psobj = $Object.PSObject
    if ($null -eq $psobj) { return $null }
    $prop = $psobj.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Add-DirectoryToPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return }
    $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -contains $Directory) { return }
    $env:Path = "$Directory;$($env:Path)"
}

function Get-ExistingExecutablePath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-PythonLauncherCommand {
    $launcherPath = Get-ExistingExecutablePath -Candidates @(
        "py",
        (Join-Path $env:WINDIR "py.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )
    if ($launcherPath) { Add-DirectoryToPath -Directory (Split-Path $launcherPath -Parent) }
    return $launcherPath
}

function Get-SystemPythonCommand {
    $pythonPath = Get-ExistingExecutablePath -Candidates @(
        # Preferir el virtualenv del repo: tiene las dependencias's dependencies (yaml, pandas,
        # etc.). A bare system Python on PATH may be missing them and will serve a
        # backend parcial/incompleto, por lo que NO debe ganar la resolucion.
        (Join-Path $script:RepoRoot ".venv\Scripts\python.exe"),
        "python",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe")
    )
    if ($pythonPath) { Add-DirectoryToPath -Directory (Split-Path $pythonPath -Parent) }
    return $pythonPath
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$CommandArgs)
    Write-Info "Ejecutando: $FilePath $($CommandArgs -join ' ')"
    & $FilePath @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        Throw-StartAllError "Comando falló (código $LASTEXITCODE): $FilePath $($CommandArgs -join ' ')"
    }
}

function Get-NpmCommand {
    $npmPath = Get-ExistingExecutablePath -Candidates @(
        "npm.cmd",
        "npm",
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
    )
    if ($npmPath) {
        Add-DirectoryToPath -Directory (Split-Path $npmPath -Parent)
        return $npmPath
    }
    Throw-StartAllError "npm no se encontró en PATH. Instala Node.js 18+."
}

function Test-ModuleAvailable {
    param([string]$PythonCommand, [string]$ModuleName)
    & $PythonCommand -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)" $ModuleName
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForHttp {
    param([string]$Url,[string]$Label,[int]$Attempts = 90)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $requestArgs = @{
                Uri        = $Url
                Method     = "Get"
                TimeoutSec = 3
            }
            # Windows PowerShell puede solicitar analisis de script a menos que se fuerce el analisis basico.
            if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
                $requestArgs["UseBasicParsing"] = $true
            }
            $r = Invoke-WebRequest @requestArgs
            Write-Info "$Label está saludable ($Url) estado=$($r.StatusCode)"
            return $true
        } catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Wait-ForLabWorker {
    param([int]$Attempts = 20)
    for ($i = 1; $i -le $Attempts; $i++) {
        $status = Get-LabWorkerStatus
        if (($null -ne $status) -and [bool]$status.active) {
            return $status
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Stop-PortListeners {
    param([int]$Port)
    $listenerPids = @(Get-ListeningProcessIds -Port $Port)
    foreach ($procId in $listenerPids) {
        if (-not $procId -or $procId -eq $PID) { continue }
        try {
            Write-WarnMessage "Deteniendo PID $procId que escucha en el puerto $Port"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            Write-WarnMessage "PID $procId no pudo detenerse directamente: $($_.Exception.Message)"
        }
    }

    $remainingPids = @(Get-ListeningProcessIds -Port $Port)
    if ($remainingPids.Count -eq 0) { return $true }

    Write-WarnMessage "Puerto $Port aún en uso por PID(s): $($remainingPids -join ', ') - se intentará reutilizar si está saludable."
    return $false
}

function Get-ListeningProcessIds {
    param([int]$Port)
    $lines = @(
        cmd /c "netstat -ano -p tcp | findstr LISTENING" 2>$null
    )
    if ($lines.Count -eq 0) { return @() }

    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($line in $lines) {
        if ($line -match "^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $linePort = [int]$matches[1]
            $linePid = [int]$matches[2]
            if ($linePort -ne $Port -or $linePid -le 0) { continue }
            [void]$pids.Add($linePid)
        }
    }
    return @($pids)
}

function Get-ListeningProcess {
    param([int]$Port)
    foreach ($procId in @(Get-ListeningProcessIds -Port $Port)) {
        try {
            return Get-Process -Id $procId -ErrorAction Stop
        } catch {
            continue
        }
    }
    return $null
}

function Get-BotProcessIds {
    $escapedRepoRoot = [Regex]::Escape($script:RepoRoot)
    try {
        return @(
            Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction Stop |
                Where-Object {
                    $cmd = [string]$_.CommandLine
                    $cmd -match $escapedRepoRoot -and (
                        $cmd -match 'from forven\.bot import run_bot' -or
                        $cmd -match '-m\s+forven(\.cli)?\s+bot' -or
                        $cmd -match '-m\s+forven\s+bot'
                    )
                } |
                Select-Object -ExpandProperty ProcessId -Unique
        )
    } catch {
        Write-WarnMessage "Descubrimiento de proceso bot falló en respaldo: $($_.Exception.Message)"
        return @()
    }
}

function Get-DescendantProcessIds {
    param([int[]]$RootProcessIds)
    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return @() }

    try {
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
    } catch {
        Write-WarnMessage "Descubrimiento de proceso descendiente falló en respaldo: $(# Requires PowerShell 5.1+
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WatchdogOwnerLockStream = $null
$script:WatchdogOwnerName = $null
$script:WatchdogOwnerAcquiredAt = $null
Set-Location $script:RepoRoot


function Write-Info { param([string]$m) Write-Host "[start_all] $m" }
function Write-WarnMessage { param([string]$m) Write-Host "[start_all][warn] $m" }
function Throw-StartAllError { param([string]$m) throw "[start_all][error] $m" }

# Busqueda segura de propiedades: bajo `Set-StrictMode -Version Latest`, reading a
# una propiedad inexistente en PSCustomObject lanza excepcion. Esto devuelve $null en su lugar
# para que los llamadores puedan usar guardas `$null -ne` en objetos derivados de JSON.
function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $psobj = $Object.PSObject
    if ($null -eq $psobj) { return $null }
    $prop = $psobj.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Add-DirectoryToPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return }
    $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -contains $Directory) { return }
    $env:Path = "$Directory;$($env:Path)"
}

function Get-ExistingExecutablePath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-PythonLauncherCommand {
    $launcherPath = Get-ExistingExecutablePath -Candidates @(
        "py",
        (Join-Path $env:WINDIR "py.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )
    if ($launcherPath) { Add-DirectoryToPath -Directory (Split-Path $launcherPath -Parent) }
    return $launcherPath
}

function Get-SystemPythonCommand {
    $pythonPath = Get-ExistingExecutablePath -Candidates @(
        # Preferir el virtualenv del repo: tiene las dependencias's dependencies (yaml, pandas,
        # etc.). A bare system Python on PATH may be missing them and will serve a
        # backend parcial/incompleto, por lo que NO debe ganar la resolucion.
        (Join-Path $script:RepoRoot ".venv\Scripts\python.exe"),
        "python",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe")
    )
    if ($pythonPath) { Add-DirectoryToPath -Directory (Split-Path $pythonPath -Parent) }
    return $pythonPath
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$CommandArgs)
    Write-Info "Ejecutando: $FilePath $($CommandArgs -join ' ')"
    & $FilePath @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        Throw-StartAllError "Comando falló (código $LASTEXITCODE): $FilePath $($CommandArgs -join ' ')"
    }
}

function Get-NpmCommand {
    $npmPath = Get-ExistingExecutablePath -Candidates @(
        "npm.cmd",
        "npm",
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
    )
    if ($npmPath) {
        Add-DirectoryToPath -Directory (Split-Path $npmPath -Parent)
        return $npmPath
    }
    Throw-StartAllError "npm no se encontró en PATH. Instala Node.js 18+."
}

function Test-ModuleAvailable {
    param([string]$PythonCommand, [string]$ModuleName)
    & $PythonCommand -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)" $ModuleName
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForHttp {
    param([string]$Url,[string]$Label,[int]$Attempts = 90)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $requestArgs = @{
                Uri        = $Url
                Method     = "Get"
                TimeoutSec = 3
            }
            # Windows PowerShell puede solicitar analisis de script a menos que se fuerce el analisis basico.
            if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
                $requestArgs["UseBasicParsing"] = $true
            }
            $r = Invoke-WebRequest @requestArgs
            Write-Info "$Label está saludable ($Url) estado=$($r.StatusCode)"
            return $true
        } catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Wait-ForLabWorker {
    param([int]$Attempts = 20)
    for ($i = 1; $i -le $Attempts; $i++) {
        $status = Get-LabWorkerStatus
        if (($null -ne $status) -and [bool]$status.active) {
            return $status
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Stop-PortListeners {
    param([int]$Port)
    $listenerPids = @(Get-ListeningProcessIds -Port $Port)
    foreach ($procId in $listenerPids) {
        if (-not $procId -or $procId -eq $PID) { continue }
        try {
            Write-WarnMessage "Deteniendo PID $procId que escucha en el puerto $Port"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            Write-WarnMessage "PID $procId no pudo detenerse directamente: $($_.Exception.Message)"
        }
    }

    $remainingPids = @(Get-ListeningProcessIds -Port $Port)
    if ($remainingPids.Count -eq 0) { return $true }

    Write-WarnMessage "Puerto $Port aún en uso por PID(s): $($remainingPids -join ', ') - se intentará reutilizar si está saludable."
    return $false
}

function Get-ListeningProcessIds {
    param([int]$Port)
    $lines = @(
        cmd /c "netstat -ano -p tcp | findstr LISTENING" 2>$null
    )
    if ($lines.Count -eq 0) { return @() }

    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($line in $lines) {
        if ($line -match "^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $linePort = [int]$matches[1]
            $linePid = [int]$matches[2]
            if ($linePort -ne $Port -or $linePid -le 0) { continue }
            [void]$pids.Add($linePid)
        }
    }
    return @($pids)
}

function Get-ListeningProcess {
    param([int]$Port)
    foreach ($procId in @(Get-ListeningProcessIds -Port $Port)) {
        try {
            return Get-Process -Id $procId -ErrorAction Stop
        } catch {
            continue
        }
    }
    return $null
}

function Get-BotProcessIds {
    $escapedRepoRoot = [Regex]::Escape($script:RepoRoot)
    try {
        return @(
            Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction Stop |
                Where-Object {
                    $cmd = [string]$_.CommandLine
                    $cmd -match $escapedRepoRoot -and (
                        $cmd -match 'from forven\.bot import run_bot' -or
                        $cmd -match '-m\s+forven(\.cli)?\s+bot' -or
                        $cmd -match '-m\s+forven\s+bot'
                    )
                } |
                Select-Object -ExpandProperty ProcessId -Unique
        )
    } catch {
        Write-WarnMessage "Descubrimiento de proceso bot falló en respaldo: $($_.Exception.Message)"
        return @()
    }
}

function Get-DescendantProcessIds {
    param([int[]]$RootProcessIds)
    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return @() }

    try {
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
    } catch {
        Write-WarnMessage "Descubrimiento de proceso descendiente falló en respaldo: $($_.Exception.Message)"
        return @()
    }

    $remaining = New-Object System.Collections.Generic.Queue[int]
    foreach ($rootPid in $roots) { $remaining.Enqueue([int]$rootPid) }
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $descendants = New-Object System.Collections.Generic.List[int]

    while ($remaining.Count -gt 0) {
        $current = $remaining.Dequeue()
        foreach ($proc in $all) {
            $parentPid = [int]$proc.ParentProcessId
            $childPid = [int]$proc.ProcessId
            if ($parentPid -ne $current -or $roots -contains $childPid) { continue }
            if ($seen.Add($childPid)) {
                $descendants.Add($childPid)
                $remaining.Enqueue($childPid)
            }
        }
    }

    return @($descendants | Select-Object -Unique)
}

function Stop-ProcessTree {
    param(
        [int[]]$RootProcessIds,
        [string]$Label
    )

    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return }

    $descendants = @(Get-DescendantProcessIds -RootProcessIds $roots)
    $allPids = @($descendants + $roots | Select-Object -Unique)
    $orderedPids = @($allPids | Sort-Object -Descending)

    foreach ($procId in $orderedPids) {
        try {
            Write-WarnMessage "Deteniendo $Label existente PID $procId"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            try {
                $stillRunning = Get-Process -Id $procId -ErrorAction SilentlyContinue
            } catch {
                $stillRunning = $null
            }
            if ($null -ne $stillRunning) {
                Throw-StartAllError "$Label existente PID $procId no pudo detenerse: $($_.Exception.Message)"
            }
        }
    }

    foreach ($procId in $orderedPids) {
        try { Wait-Process -Id $procId -Timeout 10 -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-OrphanPythonMultiprocessingProcessIds {
    try {
        $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        Write-WarnMessage "Descubrimiento de worker Python huérfano falló: $(# Requires PowerShell 5.1+
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WatchdogOwnerLockStream = $null
$script:WatchdogOwnerName = $null
$script:WatchdogOwnerAcquiredAt = $null
Set-Location $script:RepoRoot


function Write-Info { param([string]$m) Write-Host "[start_all] $m" }
function Write-WarnMessage { param([string]$m) Write-Host "[start_all][warn] $m" }
function Throw-StartAllError { param([string]$m) throw "[start_all][error] $m" }

# Busqueda segura de propiedades: bajo `Set-StrictMode -Version Latest`, reading a
# una propiedad inexistente en PSCustomObject lanza excepcion. Esto devuelve $null en su lugar
# para que los llamadores puedan usar guardas `$null -ne` en objetos derivados de JSON.
function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $psobj = $Object.PSObject
    if ($null -eq $psobj) { return $null }
    $prop = $psobj.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Add-DirectoryToPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return }
    $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -contains $Directory) { return }
    $env:Path = "$Directory;$($env:Path)"
}

function Get-ExistingExecutablePath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-PythonLauncherCommand {
    $launcherPath = Get-ExistingExecutablePath -Candidates @(
        "py",
        (Join-Path $env:WINDIR "py.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )
    if ($launcherPath) { Add-DirectoryToPath -Directory (Split-Path $launcherPath -Parent) }
    return $launcherPath
}

function Get-SystemPythonCommand {
    $pythonPath = Get-ExistingExecutablePath -Candidates @(
        # Preferir el virtualenv del repo: tiene las dependencias's dependencies (yaml, pandas,
        # etc.). A bare system Python on PATH may be missing them and will serve a
        # backend parcial/incompleto, por lo que NO debe ganar la resolucion.
        (Join-Path $script:RepoRoot ".venv\Scripts\python.exe"),
        "python",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe")
    )
    if ($pythonPath) { Add-DirectoryToPath -Directory (Split-Path $pythonPath -Parent) }
    return $pythonPath
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$CommandArgs)
    Write-Info "Ejecutando: $FilePath $($CommandArgs -join ' ')"
    & $FilePath @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        Throw-StartAllError "Comando falló (código $LASTEXITCODE): $FilePath $($CommandArgs -join ' ')"
    }
}

function Get-NpmCommand {
    $npmPath = Get-ExistingExecutablePath -Candidates @(
        "npm.cmd",
        "npm",
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
    )
    if ($npmPath) {
        Add-DirectoryToPath -Directory (Split-Path $npmPath -Parent)
        return $npmPath
    }
    Throw-StartAllError "npm no se encontró en PATH. Instala Node.js 18+."
}

function Test-ModuleAvailable {
    param([string]$PythonCommand, [string]$ModuleName)
    & $PythonCommand -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)" $ModuleName
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForHttp {
    param([string]$Url,[string]$Label,[int]$Attempts = 90)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $requestArgs = @{
                Uri        = $Url
                Method     = "Get"
                TimeoutSec = 3
            }
            # Windows PowerShell puede solicitar analisis de script a menos que se fuerce el analisis basico.
            if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
                $requestArgs["UseBasicParsing"] = $true
            }
            $r = Invoke-WebRequest @requestArgs
            Write-Info "$Label está saludable ($Url) estado=$($r.StatusCode)"
            return $true
        } catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Wait-ForLabWorker {
    param([int]$Attempts = 20)
    for ($i = 1; $i -le $Attempts; $i++) {
        $status = Get-LabWorkerStatus
        if (($null -ne $status) -and [bool]$status.active) {
            return $status
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Stop-PortListeners {
    param([int]$Port)
    $listenerPids = @(Get-ListeningProcessIds -Port $Port)
    foreach ($procId in $listenerPids) {
        if (-not $procId -or $procId -eq $PID) { continue }
        try {
            Write-WarnMessage "Deteniendo PID $procId que escucha en el puerto $Port"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            Write-WarnMessage "PID $procId no pudo detenerse directamente: $($_.Exception.Message)"
        }
    }

    $remainingPids = @(Get-ListeningProcessIds -Port $Port)
    if ($remainingPids.Count -eq 0) { return $true }

    Write-WarnMessage "Puerto $Port aún en uso por PID(s): $($remainingPids -join ', ') - se intentará reutilizar si está saludable."
    return $false
}

function Get-ListeningProcessIds {
    param([int]$Port)
    $lines = @(
        cmd /c "netstat -ano -p tcp | findstr LISTENING" 2>$null
    )
    if ($lines.Count -eq 0) { return @() }

    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($line in $lines) {
        if ($line -match "^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $linePort = [int]$matches[1]
            $linePid = [int]$matches[2]
            if ($linePort -ne $Port -or $linePid -le 0) { continue }
            [void]$pids.Add($linePid)
        }
    }
    return @($pids)
}

function Get-ListeningProcess {
    param([int]$Port)
    foreach ($procId in @(Get-ListeningProcessIds -Port $Port)) {
        try {
            return Get-Process -Id $procId -ErrorAction Stop
        } catch {
            continue
        }
    }
    return $null
}

function Get-BotProcessIds {
    $escapedRepoRoot = [Regex]::Escape($script:RepoRoot)
    try {
        return @(
            Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction Stop |
                Where-Object {
                    $cmd = [string]$_.CommandLine
                    $cmd -match $escapedRepoRoot -and (
                        $cmd -match 'from forven\.bot import run_bot' -or
                        $cmd -match '-m\s+forven(\.cli)?\s+bot' -or
                        $cmd -match '-m\s+forven\s+bot'
                    )
                } |
                Select-Object -ExpandProperty ProcessId -Unique
        )
    } catch {
        Write-WarnMessage "Descubrimiento de proceso bot falló en respaldo: $($_.Exception.Message)"
        return @()
    }
}

function Get-DescendantProcessIds {
    param([int[]]$RootProcessIds)
    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return @() }

    try {
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
    } catch {
        Write-WarnMessage "Descubrimiento de proceso descendiente falló en respaldo: $($_.Exception.Message)"
        return @()
    }

    $remaining = New-Object System.Collections.Generic.Queue[int]
    foreach ($rootPid in $roots) { $remaining.Enqueue([int]$rootPid) }
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $descendants = New-Object System.Collections.Generic.List[int]

    while ($remaining.Count -gt 0) {
        $current = $remaining.Dequeue()
        foreach ($proc in $all) {
            $parentPid = [int]$proc.ParentProcessId
            $childPid = [int]$proc.ProcessId
            if ($parentPid -ne $current -or $roots -contains $childPid) { continue }
            if ($seen.Add($childPid)) {
                $descendants.Add($childPid)
                $remaining.Enqueue($childPid)
            }
        }
    }

    return @($descendants | Select-Object -Unique)
}

function Stop-ProcessTree {
    param(
        [int[]]$RootProcessIds,
        [string]$Label
    )

    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return }

    $descendants = @(Get-DescendantProcessIds -RootProcessIds $roots)
    $allPids = @($descendants + $roots | Select-Object -Unique)
    $orderedPids = @($allPids | Sort-Object -Descending)

    foreach ($procId in $orderedPids) {
        try {
            Write-WarnMessage "Deteniendo $Label existente PID $procId"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            try {
                $stillRunning = Get-Process -Id $procId -ErrorAction SilentlyContinue
            } catch {
                $stillRunning = $null
            }
            if ($null -ne $stillRunning) {
                Throw-StartAllError "$Label existente PID $procId no pudo detenerse: $($_.Exception.Message)"
            }
        }
    }

    foreach ($procId in $orderedPids) {
        try { Wait-Process -Id $procId -Timeout 10 -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-OrphanPythonMultiprocessingProcessIds {
    try {
        $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        Write-WarnMessage "Descubrimiento de worker Python huerfano fallo: $($_.Exception.Message)"
        return @()
    }

    $liveProcessIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($proc in $allProcesses) {
        [void]$liveProcessIds.Add([int]$proc.ProcessId)
    }

    return @(
        $allProcesses |
            Where-Object {
                $cmd = [string]$_.CommandLine
                $cmd -match 'multiprocessing\.spawn' -and
                    $cmd -match 'spawn_main' -and
                    -not $liveProcessIds.Contains([int]$_.ParentProcessId)
            } |
            Select-Object -ExpandProperty ProcessId -Unique
    )
}

function Stop-OrphanPythonMultiprocessingProcesses {
    $orphanPids = @(Get-OrphanPythonMultiprocessingProcessIds)
    if ($orphanPids.Count -eq 0) { return }

    Write-WarnMessage "Deteniendo worker Python multiprocessing huérfano PID(s): $($orphanPids -join ', ')"
    foreach ($procId in $orphanPids) {
        try {
            Stop-Process -Id ([int]$procId) -Force -ErrorAction Stop
        } catch {
            Write-WarnMessage "Worker Python huérfano PID $procId no pudo detenerse: $(# Requires PowerShell 5.1+
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WatchdogOwnerLockStream = $null
$script:WatchdogOwnerName = $null
$script:WatchdogOwnerAcquiredAt = $null
Set-Location $script:RepoRoot


function Write-Info { param([string]$m) Write-Host "[start_all] $m" }
function Write-WarnMessage { param([string]$m) Write-Host "[start_all][warn] $m" }
function Throw-StartAllError { param([string]$m) throw "[start_all][error] $m" }

# Busqueda segura de propiedades: bajo `Set-StrictMode -Version Latest`, reading a
# una propiedad inexistente en PSCustomObject lanza excepcion. Esto devuelve $null en su lugar
# para que los llamadores puedan usar guardas `$null -ne` en objetos derivados de JSON.
function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $psobj = $Object.PSObject
    if ($null -eq $psobj) { return $null }
    $prop = $psobj.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Add-DirectoryToPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return }
    $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -contains $Directory) { return }
    $env:Path = "$Directory;$($env:Path)"
}

function Get-ExistingExecutablePath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-PythonLauncherCommand {
    $launcherPath = Get-ExistingExecutablePath -Candidates @(
        "py",
        (Join-Path $env:WINDIR "py.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )
    if ($launcherPath) { Add-DirectoryToPath -Directory (Split-Path $launcherPath -Parent) }
    return $launcherPath
}

function Get-SystemPythonCommand {
    $pythonPath = Get-ExistingExecutablePath -Candidates @(
        # Preferir el virtualenv del repo: tiene las dependencias's dependencies (yaml, pandas,
        # etc.). A bare system Python on PATH may be missing them and will serve a
        # backend parcial/incompleto, por lo que NO debe ganar la resolucion.
        (Join-Path $script:RepoRoot ".venv\Scripts\python.exe"),
        "python",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe")
    )
    if ($pythonPath) { Add-DirectoryToPath -Directory (Split-Path $pythonPath -Parent) }
    return $pythonPath
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$CommandArgs)
    Write-Info "Ejecutando: $FilePath $($CommandArgs -join ' ')"
    & $FilePath @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        Throw-StartAllError "Comando falló (código $LASTEXITCODE): $FilePath $($CommandArgs -join ' ')"
    }
}

function Get-NpmCommand {
    $npmPath = Get-ExistingExecutablePath -Candidates @(
        "npm.cmd",
        "npm",
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
    )
    if ($npmPath) {
        Add-DirectoryToPath -Directory (Split-Path $npmPath -Parent)
        return $npmPath
    }
    Throw-StartAllError "npm no se encontró en PATH. Instala Node.js 18+."
}

function Test-ModuleAvailable {
    param([string]$PythonCommand, [string]$ModuleName)
    & $PythonCommand -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)" $ModuleName
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForHttp {
    param([string]$Url,[string]$Label,[int]$Attempts = 90)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $requestArgs = @{
                Uri        = $Url
                Method     = "Get"
                TimeoutSec = 3
            }
            # Windows PowerShell puede solicitar analisis de script a menos que se fuerce el analisis basico.
            if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
                $requestArgs["UseBasicParsing"] = $true
            }
            $r = Invoke-WebRequest @requestArgs
            Write-Info "$Label está saludable ($Url) estado=$($r.StatusCode)"
            return $true
        } catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Wait-ForLabWorker {
    param([int]$Attempts = 20)
    for ($i = 1; $i -le $Attempts; $i++) {
        $status = Get-LabWorkerStatus
        if (($null -ne $status) -and [bool]$status.active) {
            return $status
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Stop-PortListeners {
    param([int]$Port)
    $listenerPids = @(Get-ListeningProcessIds -Port $Port)
    foreach ($procId in $listenerPids) {
        if (-not $procId -or $procId -eq $PID) { continue }
        try {
            Write-WarnMessage "Deteniendo PID $procId que escucha en el puerto $Port"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            Write-WarnMessage "PID $procId no pudo detenerse directamente: $($_.Exception.Message)"
        }
    }

    $remainingPids = @(Get-ListeningProcessIds -Port $Port)
    if ($remainingPids.Count -eq 0) { return $true }

    Write-WarnMessage "Puerto $Port aún en uso por PID(s): $($remainingPids -join ', ') - se intentará reutilizar si está saludable."
    return $false
}

function Get-ListeningProcessIds {
    param([int]$Port)
    $lines = @(
        cmd /c "netstat -ano -p tcp | findstr LISTENING" 2>$null
    )
    if ($lines.Count -eq 0) { return @() }

    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($line in $lines) {
        if ($line -match "^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $linePort = [int]$matches[1]
            $linePid = [int]$matches[2]
            if ($linePort -ne $Port -or $linePid -le 0) { continue }
            [void]$pids.Add($linePid)
        }
    }
    return @($pids)
}

function Get-ListeningProcess {
    param([int]$Port)
    foreach ($procId in @(Get-ListeningProcessIds -Port $Port)) {
        try {
            return Get-Process -Id $procId -ErrorAction Stop
        } catch {
            continue
        }
    }
    return $null
}

function Get-BotProcessIds {
    $escapedRepoRoot = [Regex]::Escape($script:RepoRoot)
    try {
        return @(
            Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction Stop |
                Where-Object {
                    $cmd = [string]$_.CommandLine
                    $cmd -match $escapedRepoRoot -and (
                        $cmd -match 'from forven\.bot import run_bot' -or
                        $cmd -match '-m\s+forven(\.cli)?\s+bot' -or
                        $cmd -match '-m\s+forven\s+bot'
                    )
                } |
                Select-Object -ExpandProperty ProcessId -Unique
        )
    } catch {
        Write-WarnMessage "Descubrimiento de proceso bot falló en respaldo: $($_.Exception.Message)"
        return @()
    }
}

function Get-DescendantProcessIds {
    param([int[]]$RootProcessIds)
    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return @() }

    try {
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
    } catch {
        Write-WarnMessage "Descubrimiento de proceso descendiente falló en respaldo: $(# Requires PowerShell 5.1+
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WatchdogOwnerLockStream = $null
$script:WatchdogOwnerName = $null
$script:WatchdogOwnerAcquiredAt = $null
Set-Location $script:RepoRoot


function Write-Info { param([string]$m) Write-Host "[start_all] $m" }
function Write-WarnMessage { param([string]$m) Write-Host "[start_all][warn] $m" }
function Throw-StartAllError { param([string]$m) throw "[start_all][error] $m" }

# Busqueda segura de propiedades: bajo `Set-StrictMode -Version Latest`, reading a
# una propiedad inexistente en PSCustomObject lanza excepcion. Esto devuelve $null en su lugar
# para que los llamadores puedan usar guardas `$null -ne` en objetos derivados de JSON.
function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $psobj = $Object.PSObject
    if ($null -eq $psobj) { return $null }
    $prop = $psobj.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Add-DirectoryToPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return }
    $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -contains $Directory) { return }
    $env:Path = "$Directory;$($env:Path)"
}

function Get-ExistingExecutablePath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-PythonLauncherCommand {
    $launcherPath = Get-ExistingExecutablePath -Candidates @(
        "py",
        (Join-Path $env:WINDIR "py.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )
    if ($launcherPath) { Add-DirectoryToPath -Directory (Split-Path $launcherPath -Parent) }
    return $launcherPath
}

function Get-SystemPythonCommand {
    $pythonPath = Get-ExistingExecutablePath -Candidates @(
        # Preferir el virtualenv del repo: tiene las dependencias's dependencies (yaml, pandas,
        # etc.). A bare system Python on PATH may be missing them and will serve a
        # backend parcial/incompleto, por lo que NO debe ganar la resolucion.
        (Join-Path $script:RepoRoot ".venv\Scripts\python.exe"),
        "python",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe")
    )
    if ($pythonPath) { Add-DirectoryToPath -Directory (Split-Path $pythonPath -Parent) }
    return $pythonPath
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$CommandArgs)
    Write-Info "Ejecutando: $FilePath $($CommandArgs -join ' ')"
    & $FilePath @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        Throw-StartAllError "Comando falló (código $LASTEXITCODE): $FilePath $($CommandArgs -join ' ')"
    }
}

function Get-NpmCommand {
    $npmPath = Get-ExistingExecutablePath -Candidates @(
        "npm.cmd",
        "npm",
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
    )
    if ($npmPath) {
        Add-DirectoryToPath -Directory (Split-Path $npmPath -Parent)
        return $npmPath
    }
    Throw-StartAllError "npm no se encontró en PATH. Instala Node.js 18+."
}

function Test-ModuleAvailable {
    param([string]$PythonCommand, [string]$ModuleName)
    & $PythonCommand -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)" $ModuleName
    return ($LASTEXITCODE -eq 0)
}

function Wait-ForHttp {
    param([string]$Url,[string]$Label,[int]$Attempts = 90)
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $requestArgs = @{
                Uri        = $Url
                Method     = "Get"
                TimeoutSec = 3
            }
            # Windows PowerShell puede solicitar analisis de script a menos que se fuerce el analisis basico.
            if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey("UseBasicParsing")) {
                $requestArgs["UseBasicParsing"] = $true
            }
            $r = Invoke-WebRequest @requestArgs
            Write-Info "$Label está saludable ($Url) estado=$($r.StatusCode)"
            return $true
        } catch { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Wait-ForLabWorker {
    param([int]$Attempts = 20)
    for ($i = 1; $i -le $Attempts; $i++) {
        $status = Get-LabWorkerStatus
        if (($null -ne $status) -and [bool]$status.active) {
            return $status
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Stop-PortListeners {
    param([int]$Port)
    $listenerPids = @(Get-ListeningProcessIds -Port $Port)
    foreach ($procId in $listenerPids) {
        if (-not $procId -or $procId -eq $PID) { continue }
        try {
            Write-WarnMessage "Deteniendo PID $procId que escucha en el puerto $Port"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            Write-WarnMessage "PID $procId no pudo detenerse directamente: $($_.Exception.Message)"
        }
    }

    $remainingPids = @(Get-ListeningProcessIds -Port $Port)
    if ($remainingPids.Count -eq 0) { return $true }

    Write-WarnMessage "Puerto $Port aún en uso por PID(s): $($remainingPids -join ', ') - se intentará reutilizar si está saludable."
    return $false
}

function Get-ListeningProcessIds {
    param([int]$Port)
    $lines = @(
        cmd /c "netstat -ano -p tcp | findstr LISTENING" 2>$null
    )
    if ($lines.Count -eq 0) { return @() }

    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($line in $lines) {
        if ($line -match "^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            $linePort = [int]$matches[1]
            $linePid = [int]$matches[2]
            if ($linePort -ne $Port -or $linePid -le 0) { continue }
            [void]$pids.Add($linePid)
        }
    }
    return @($pids)
}

function Get-ListeningProcess {
    param([int]$Port)
    foreach ($procId in @(Get-ListeningProcessIds -Port $Port)) {
        try {
            return Get-Process -Id $procId -ErrorAction Stop
        } catch {
            continue
        }
    }
    return $null
}

function Get-BotProcessIds {
    $escapedRepoRoot = [Regex]::Escape($script:RepoRoot)
    try {
        return @(
            Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction Stop |
                Where-Object {
                    $cmd = [string]$_.CommandLine
                    $cmd -match $escapedRepoRoot -and (
                        $cmd -match 'from forven\.bot import run_bot' -or
                        $cmd -match '-m\s+forven(\.cli)?\s+bot' -or
                        $cmd -match '-m\s+forven\s+bot'
                    )
                } |
                Select-Object -ExpandProperty ProcessId -Unique
        )
    } catch {
        Write-WarnMessage "Descubrimiento de proceso bot falló en respaldo: $($_.Exception.Message)"
        return @()
    }
}

function Get-DescendantProcessIds {
    param([int[]]$RootProcessIds)
    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return @() }

    try {
        $all = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId,ParentProcessId)
    } catch {
        Write-WarnMessage "Descubrimiento de proceso descendiente falló en respaldo: $($_.Exception.Message)"
        return @()
    }

    $remaining = New-Object System.Collections.Generic.Queue[int]
    foreach ($rootPid in $roots) { $remaining.Enqueue([int]$rootPid) }
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $descendants = New-Object System.Collections.Generic.List[int]

    while ($remaining.Count -gt 0) {
        $current = $remaining.Dequeue()
        foreach ($proc in $all) {
            $parentPid = [int]$proc.ParentProcessId
            $childPid = [int]$proc.ProcessId
            if ($parentPid -ne $current -or $roots -contains $childPid) { continue }
            if ($seen.Add($childPid)) {
                $descendants.Add($childPid)
                $remaining.Enqueue($childPid)
            }
        }
    }

    return @($descendants | Select-Object -Unique)
}

function Stop-ProcessTree {
    param(
        [int[]]$RootProcessIds,
        [string]$Label
    )

    $roots = @($RootProcessIds | Where-Object { $_ -and $_ -gt 0 } | Select-Object -Unique)
    if ($roots.Count -eq 0) { return }

    $descendants = @(Get-DescendantProcessIds -RootProcessIds $roots)
    $allPids = @($descendants + $roots | Select-Object -Unique)
    $orderedPids = @($allPids | Sort-Object -Descending)

    foreach ($procId in $orderedPids) {
        try {
            Write-WarnMessage "Deteniendo $Label existente PID $procId"
            Stop-Process -Id $procId -Force -ErrorAction Stop
        } catch {
            try {
                $stillRunning = Get-Process -Id $procId -ErrorAction SilentlyContinue
            } catch {
                $stillRunning = $null
            }
            if ($null -ne $stillRunning) {
                Throw-StartAllError "$Label existente PID $procId no pudo detenerse: $($_.Exception.Message)"
            }
        }
    }

    foreach ($procId in $orderedPids) {
        try { Wait-Process -Id $procId -Timeout 10 -ErrorAction SilentlyContinue } catch {}
    }
}

function Get-OrphanPythonMultiprocessingProcessIds {
    try {
        $allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        Write-WarnMessage "Descubrimiento de worker Python huérfano falló: $(# Requires PowerShell 5.1+
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:WatchdogOwnerLockStream = $null
$script:WatchdogOwnerName = $null
$script:WatchdogOwnerAcquiredAt = $null
Set-Location $script:RepoRoot


function Write-Info { param([string]$m) Write-Host "[start_all] $m" }
function Write-WarnMessage { param([string]$m) Write-Host "[start_all][warn] $m" }
function Throw-StartAllError { param([string]$m) throw "[start_all][error] $m" }

# Busqueda segura de propiedades: bajo `Set-StrictMode -Version Latest`, reading a
# una propiedad inexistente en PSCustomObject lanza excepcion. Esto devuelve $null en su lugar
# para que los llamadores puedan usar guardas `$null -ne` en objetos derivados de JSON.
function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $psobj = $Object.PSObject
    if ($null -eq $psobj) { return $null }
    $prop = $psobj.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Add-DirectoryToPath {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return }
    $pathEntries = @($env:Path -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -contains $Directory) { return }
    $env:Path = "$Directory;$($env:Path)"
}

function Get-ExistingExecutablePath {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    return $null
}

function Get-PythonLauncherCommand {
    $launcherPath = Get-ExistingExecutablePath -Candidates @(
        "py",
        (Join-Path $env:WINDIR "py.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    )
    if ($launcherPath) { Add-DirectoryToPath -Directory (Split-Path $launcherPath -Parent) }
    return $launcherPath
}

function Get-SystemPythonCommand {
    $pythonPath = Get-ExistingExecutablePath -Candidates @(
        # Preferir el virtualenv del repo: tiene las dependencias's dependencies (yaml, pandas,
        # etc.). A bare system Python on PATH may be missing them and will serve a
        # backend parcial/incompleto, por lo que NO debe ganar la resolucion.
        (Join-Path $script:RepoRoot ".venv\Scripts\python.exe"),
        "python",
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python311\python.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Python312\python.exe")
    )
    if ($pythonPath) { Add-DirectoryToPath -Directory (Split-Path $pythonPath -Parent) }
    return $pythonPath
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$CommandArgs)
    Write-Info "Ejecutando: $FilePath $($CommandArgs -join ' ')"
    & $FilePath @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        Throw-StartAllError "Comando falló (código $LASTEXITCODE): $FilePath $($CommandArgs -join ' ')"
    }
}

function Get-NpmCommand {
    $npmPath = Get-ExistingExecutablePath -Candidates @(
        "npm.cmd",
        "npm",
        (Join-Path $env:ProgramFiles "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
    )
    if ($npmPath) {
        Add-DirectoryToPath -Directory (Split-Path $npmPath -Parent)
        return $npmPath
    }
    Throw-StartAllError "npm no se encontró en PATH. Instala Node.js 18+."
}

function Test-ModuleAvailable {
