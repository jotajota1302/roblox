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

# EL FORMATO IMPORTA MAS DE LO QUE PARECE, y esto se aprendio subiendo la portada de
# verdad: la MINIATURA en PNG pesaba 4 MB y el portal de Roblox no la aceptaba -- el
# formulario se quedaba sin reaccionar, sin decir por que. En JPEG de calidad 92 pesa
# 301 KB y entra sin protestar.
#
# El ICONO se queda en PNG a proposito: se ve a 150 px y con mucho contraste, y ahi los
# artefactos del JPEG se notan justo en los bordes duros. A 512x512 pesa medio mega, que
# no es problema para nadie.
function ConvertirJpeg($fichero, $salida, $ancho, $alto) {
    $img = [System.Drawing.Image]::FromFile($fichero)
    $lienzo = New-Object System.Drawing.Bitmap($ancho, $alto)
    $g = [System.Drawing.Graphics]::FromImage($lienzo)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.DrawImage($img, 0, 0, $ancho, $alto)
    $g.Dispose()
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $par = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $par.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]92)
    $lienzo.Save($salida, $codec, $par)
    $lienzo.Dispose()
    $img.Dispose()
    $kb = [math]::Round((Get-Item $salida).Length / 1KB)
    "  OK  {0,-28} {1} x {2}  ({3} KB)" -f (Split-Path $salida -Leaf), $ancho, $alto, $kb
}

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
ConvertirJpeg (Join-Path $origen "miniatura-b.jpg") (Join-Path $destino "MINIATURA-1920.jpg") 1920 1080
# Las dos alternativas, listas por si hay que rotar la portada para subir el CTR.
Convertir (Join-Path $origen "icono-c.jpg")     (Join-Path $destino "alternativa-ICONO-512.png") 512 512
ConvertirJpeg (Join-Path $origen "miniatura-c.jpg") (Join-Path $destino "secundaria-CIUDAD-1920.jpg") 1920 1080
""
"Listo en: assets\portada\listo\"
