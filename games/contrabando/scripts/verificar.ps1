# verificar.ps1 — la pasada que hay que dar ANTES de decir que algo funciona.
#
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\verificar.ps1
#
# POR QUÉ EXISTE EL PASO 2, que es el nuevo. El 20/08 el sistema de señales del
# cliente llevaba días muerto: `Senales.reunir()` escribía en una tabla que se había
# borrado al quitar los faroles, así que reventaba en su primera línea. La llamada va
# envuelta en un pcall, de modo que el juego arrancaba igual y lo único que se veía
# era el mundo con TODO encendido a la vez. De ahí salieron cuatro quejas seguidas
# —el rail parpadeando, los paquetes que no desaparecen, el minimapa ilegible— y
# ninguna se parecía a "hay una variable que no existe".
#
# stylua no lo caza (es formato) y `rojo build` tampoco (compila de sobra). Lo caza un
# analizador estático en un segundo, y lo caza SIEMPRE.
#
# Se bloquea sólo con la familia `Unknown global` / `Unknown symbol`: en todo el
# proyecto hay CERO avisos de esa clase cuando está sano, así que no hay ruido que
# filtrar y cualquiera que aparezca es un bug de verdad. Los errores de tipos —200 y
# pico, casi todos inferencia de tablas heterogéneas— se cuentan pero no bloquean:
# convertirlos en bloqueantes hoy significaría desactivar el paso mañana.

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$tools = Join-Path (Split-Path -Parent (Split-Path -Parent $raiz)) "tools"
Set-Location $raiz

$fallos = 0

Write-Host "`n[1/4] formato y sintaxis (stylua)" -ForegroundColor Cyan
& (Join-Path $tools "stylua.exe") --check src
if ($LASTEXITCODE -ne 0) { Write-Host "  X formato" -ForegroundColor Red; $fallos++ }
else { Write-Host "  OK" -ForegroundColor Green }

Write-Host "`n[2/4] analisis estatico (luau-lsp)" -ForegroundColor Cyan
$lsp = Join-Path $tools "luau-lsp.exe"
$defs = Join-Path $tools "globalTypes.d.luau"
if (-not (Test-Path $lsp) -or -not (Test-Path $defs)) {
    Write-Host "  ! falta luau-lsp o globalTypes: ejecuta setup.ps1" -ForegroundColor Yellow
} else {
    & (Join-Path $tools "rojo.exe") sourcemap default.project.json --output sourcemap.json | Out-Null
    # LUAU-LSP ESCRIBE SUS HALLAZGOS POR STDERR, NO POR STDOUT. Las dos primeras
    # versiones de esta linea daban verde SIEMPRE y por motivos opuestos: con `2>&1`,
    # PowerShell 5.1 envuelve cada linea de stderr en un ErrorRecord y --con
    # $ErrorActionPreference en "Stop"-- el script moria en el [INFO] de arranque; con
    # `2>$null` no moria, pero tiraba justo lo unico que hay que leer y anunciaba "0
    # avisos" con 833 esperando. Una sonda que no puede fallar nunca es peor que no
    # tenerla: da permiso para no mirar.
    #
    # La redireccion se hace en cmd, FUERA de PowerShell, asi que aqui llega todo por
    # stdout y como texto. Y hay una prueba de que esto funciona: se reintrodujo el
    # fallo de `rutaDeGuarida` a proposito y el paso 2 lo cazo.
    $orden = '"' + $lsp + '" analyze "--definitions=' + $defs + '" "--sourcemap=sourcemap.json" src 2>&1'
    $salida = cmd /c $orden
    # `Unknown require: unsupported path` es esperado y correcto: Main.server carga sus
    # modulos con WaitForChild dentro de un pcall, a proposito, para que un modulo que
    # falle no se lleve por delante el arranque entero. El analizador no puede seguir
    # una ruta dinamica, y eso no es un defecto del codigo.
    $graves = $salida | Where-Object { $_ -match "Unknown global|Unknown symbol" }
    $tipos = ($salida | Where-Object { $_ -match "TypeError" }).Count
    if ($graves.Count -gt 0) {
        Write-Host "  X $($graves.Count) simbolo(s) que no existen -- esto SIEMPRE es un bug:" -ForegroundColor Red
        $graves | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
        $fallos++
    } else {
        Write-Host "  OK  ningun simbolo inexistente  ($tipos avisos de tipos, informativos)" -ForegroundColor Green
    }
}

Write-Host "`n[3/4] compila (rojo build)" -ForegroundColor Cyan
# AL FICHERO DEL PROYECTO, nunca a un temporal: es el que JJ abre con doble clic, y
# compilar a otro sitio produce el peor resultado posible -- yo verifico una version
# y el juega otra. Ya paso.
& (Join-Path $tools "rojo.exe") build --output contrabando.rbxl | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "  X no compila" -ForegroundColor Red; $fallos++ }
else { Write-Host "  OK  -> contrabando.rbxl" -ForegroundColor Green }

Write-Host "`n[4/4] lo que NO se puede comprobar aqui" -ForegroundColor Cyan
Write-Host "  - las 854 pruebas puras y las 77 sondas del mundo: en Studio" -ForegroundColor DarkGray
Write-Host "  - que se vea bien: jugando. Que compile no significa que funcione" -ForegroundColor DarkGray

if ($fallos -gt 0) {
    Write-Host "`nFALLOS: $fallos`n" -ForegroundColor Red
    exit 1
}
Write-Host "`nTODO OK`n" -ForegroundColor Green
