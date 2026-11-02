param(
  [string]$Out = 'D:\palette.png',
  [string]$Colors = ''
)
# Draw a swatch chart (6 x 4 chips) from comma-separated hex colors.
# ASCII-only script on purpose: avoids PowerShell 5 ANSI/UTF-8 script decoding traps.

Add-Type -AssemblyName System.Drawing

$list = @($Colors.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if ($list.Count -eq 0) { throw 'No colors given.' }

$cols = 6
$rows = [int][Math]::Ceiling($list.Count / $cols)
$chipW = 160; $chipH = 110; $gap = 14; $labelH = 30; $pad = 28
$w = $pad * 2 + $cols * $chipW + ($cols - 1) * $gap
$h = $pad * 2 + $rows * ($chipH + $labelH) + ($rows - 1) * $gap

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.Clear([System.Drawing.Color]::FromArgb(18, 20, 30))

$font = New-Object System.Drawing.Font('Consolas', 13, [System.Drawing.FontStyle]::Bold)
$labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 232, 240))

for ($i = 0; $i -lt $list.Count; $i++) {
  $hex = $list[$i].ToUpper()
  if ($hex.Length -ne 6) { throw ("Bad hex: " + $hex) }
  $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
  $gg = [Convert]::ToInt32($hex.Substring(2, 2), 16)
  $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
  $col = [System.Drawing.Color]::FromArgb($r, $gg, $b)

  $row = [int][Math]::Floor($i / $cols)
  $c = $i % $cols
  $x = $pad + $c * ($chipW + $gap)
  $y = $pad + $row * ($chipH + $labelH + $gap)

  $fill = New-Object System.Drawing.SolidBrush($col)
  $g.FillRectangle($fill, $x, $y, $chipW, $chipH)
  $g.DrawString(('#' + $hex), $font, $labelBrush, $x, ($y + $chipH + 3))
  $fill.Dispose()
}

$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ('OK -> ' + $Out)
