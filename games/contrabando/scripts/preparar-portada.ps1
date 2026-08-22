# preparar-portada.ps1 — deja el icono y la miniatura en el tamano EXACTO que pide Roblox.
#
# POR QUE HACE FALTA. MiniMax devuelve 1024x1024 y 1280x720, y el portal pide 512x512 y
# 1920x1080. Roblox acepta otros tamanos y los reescala el mismo, pero lo hace con su
# algoritmo y sobre la marcha: dandoselo ya en su medida, lo que se ve en la cuadricula es
# exactamente lo que hemos mirado nosotros. En una imagen que se juega el CTR, eso importa.
#
# Uso:  powershell -ExecutionPolicy Bypass -File scripts\preparar-portada.ps1
# Sale en: assets\portada\listo\

Add-Type -AssemblyName System.Drawing

$raiz = Split-Path -Parent $PSScriptRoot
$origen = Join-Path $raiz "assets\portada"
$destino = Join-Path $origen "listo"
if (-not (Test-Path $destino)) { New-Item -ItemType Directory -Path $destino | Out-Null }

function Convertir($fichero, $salida, $ancho, $alto) {
    $img = [System.Drawing.Image]::FromFile($fichero)
    $lienzo = New-Object System.Drawing.Bitmap($ancho, $alto)
    $g = [System.Drawing.Graphics]::FromImage($lienzo)
    # Bicubico de alta calidad: bajar de 1024 a 512 con el modo por defecto deja bordes
    # sucios, y estas imagenes se ven a 150 px donde cada borde cuenta.
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($img, 0, 0, $ancho, $alto)
    $g.Dispose()
    # PNG: el icono se ve pequeno y con mucho contraste, y ahi los artefactos del JPEG se
    # notan en los bordes duros. Pesa mas y da igual, se sube una vez.
    $lienzo.Save($salida, [System.Drawing.Imaging.ImageFormat]::Png)
    $lienzo.Dispose()
    $img.Dispose()
    $kb = [math]::Round((Get-Item $salida).Length / 1KB)
    "  OK  {0,-28} {1} x {2}  ({3} KB)" -f (Split-Path $salida -Leaf), $ancho, $alto, $kb
}

"Preparando la portada para el portal de Roblox:"
Convertir (Join-Path $origen "icono-a.jpg")     (Join-Path $destino "ICONO-512.png")            512  512
Convertir (Join-Path $origen "miniatura-b.jpg") (Join-Path $destino "MINIATURA-1920.png")      1920 1080
# Las dos alternativas, listas por si hay que rotar la portada para subir el CTR.
Convertir (Join-Path $origen "icono-c.jpg")     (Join-Path $destino "alternativa-ICONO-512.png") 512 512
Convertir (Join-Path $origen "miniatura-c.jpg") (Join-Path $destino "secundaria-CIUDAD-1920.png") 1920 1080
""
"Listo en: assets\portada\listo\"
