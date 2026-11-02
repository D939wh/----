param(
  [string]$OutSheet = 'D:\sheet.png',
  [string]$OutPreview = 'D:\preview.png',
  [string]$OutScene = 'D:\scene.png'
)
# Placeholder 16x16 pixel tiles + assembled corridor sample, drawn with the
# project 24-color palette. ASCII-only script on purpose (Chinese only via
# arguments): avoids PowerShell 5.1 script-decoding traps.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Palette: single letter -> hex from the project palette (24-color draft)
$COL = @{
  A='12162A'; B='2A3050'; C='101528'; D='1B2440'; E='26305A'; F='35406E'
  G='6B7280'; H='5A6078'; I='4A5D4E'; J='B8BFD0'; K='E8EAF0'; L='D9534F'
  M='F2C777'; N='FFE7B0'; O='D8A75A'; P='6E5A46'; Q='8A7360'; R='F2C9A0'
}
$script:BR = @{}
foreach ($key in $COL.Keys) {
  $hex = $COL[$key]
  $r = [Convert]::ToInt32($hex.Substring(0,2),16)
  $gg = [Convert]::ToInt32($hex.Substring(2,2),16)
  $bb = [Convert]::ToInt32($hex.Substring(4,2),16)
  $script:BR[$key] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($r,$gg,$bb))
}
function Rect($ch, $x, $y, $w, $h) {
  $script:g.FillRectangle($script:BR[$ch], [int]$x, [int]$y, [int]$w, [int]$h)
}

# ---------------- tile painters (16x16 at ox,oy) ----------------
function Tile-FloorA($ox,$oy){          # light tile with grout
  Rect 'G' $ox $oy 16 16
  Rect 'H' $ox $oy 16 1
  Rect 'H' $ox $oy 1 16
  Rect 'J' ($ox+5) ($oy+3) 1 1
  Rect 'H' ($ox+9) ($oy+7) 1 1
  Rect 'J' ($ox+12) ($oy+12) 1 1
  Rect 'H' ($ox+3) ($oy+11) 1 1
}
function Tile-FloorB($ox,$oy){          # darker tile
  Rect 'H' $ox $oy 16 16
  Rect 'G' $ox $oy 16 1
  Rect 'G' $ox $oy 1 16
  Rect 'G' ($ox+4) ($oy+5) 1 1
  Rect 'G' ($ox+11) ($oy+9) 1 1
  Rect 'A' ($ox+7) ($oy+13) 1 1
}
function Tile-FloorC($ox,$oy){          # stained tile
  Rect 'G' $ox $oy 16 16
  Rect 'H' $ox $oy 16 1
  Rect 'H' $ox $oy 1 16
  Rect 'H' ($ox+10) ($oy+9) 3 3
  Rect 'A' ($ox+11) ($oy+11) 1 1
  Rect 'J' ($ox+4) ($oy+4) 1 1
}
function Tile-Ceiling($ox,$oy){
  Rect 'C' $ox $oy 16 16
  Rect 'A' $ox $oy 16 1
  Rect 'B' $ox ($oy+6) 16 2
  Rect 'A' $ox ($oy+12) 16 1
}
function Tile-WallNoise($ox,$oy){        # mottled wall (mid blue)
  Rect 'E' $ox $oy 16 16
  Rect 'D' ($ox+2) ($oy+3) 2 2
  Rect 'F' ($ox+11) ($oy+5) 2 2
  Rect 'D' ($ox+6) ($oy+11) 2 2
  Rect 'C' ($ox+8) ($oy+2) 1 2
  Rect 'C' ($ox+14) ($oy+9) 1 2
  Rect 'C' ($ox+4) ($oy+13) 1 2
  Rect 'A' ($ox+7) ($oy+7) 1 1
  Rect 'D' ($ox+13) ($oy+2) 1 1
}
function Tile-WallPeel($ox,$oy){         # peeling paint
  Rect 'F' $ox $oy 16 16
  Rect 'K' ($ox+5) ($oy+4) 3 2
  Rect 'A' ($ox+5) ($oy+4) 1 1
  Rect 'A' ($ox+10) ($oy+9) 2 1
  Rect 'D' ($ox+2) ($oy+12) 2 1
  Rect 'C' ($ox+13) ($oy+6) 2 2
}
function Tile-WallSkirt($ox,$oy){        # green wainscot
  Rect 'I' $ox $oy 16 16
  Rect 'B' $ox $oy 16 1
  Rect 'B' $ox ($oy+15) 16 1
  Rect 'A' ($ox+4) ($oy+7) 1 1
  Rect 'A' ($ox+11) ($oy+11) 1 1
  Rect 'A' ($ox+13) ($oy+4) 1 1
}
function Tile-AdRed($ox,$oy){            # red poster on wall
  Rect 'E' $ox $oy 16 16
  Rect 'A' ($ox+3) ($oy+4) 10 7
  Rect 'L' ($ox+4) ($oy+5) 8 5
  Rect 'K' ($ox+5) ($oy+6) 3 1
  Rect 'J' ($ox+5) ($oy+8) 6 1
  Rect 'J' ($ox+10) ($oy+7) 1 2
}
function Tile-AdWhite($ox,$oy){          # white notice on wall
  Rect 'E' $ox $oy 16 16
  Rect 'A' ($ox+4) ($oy+4) 9 7
  Rect 'K' ($ox+5) ($oy+5) 7 5
  Rect 'J' ($ox+6) ($oy+6) 5 1
  Rect 'J' ($ox+6) ($oy+8) 4 1
  Rect 'H' ($ox+9) ($oy+7) 1 1
}
function Tile-Window($ox,$oy){
  Rect 'E' $ox $oy 16 16
  Rect 'H' ($ox+2) ($oy+2) 12 11
  Rect 'F' ($ox+2) ($oy+2) 12 1
  Rect 'C' ($ox+3) ($oy+3) 10 9
  Rect 'J' ($ox+8) ($oy+3) 1 9
  Rect 'J' ($ox+3) ($oy+7) 10 1
}
function Tile-DoorTopL($ox,$oy){         # door upper, left half
  Rect 'E' $ox $oy 16 16
  Rect 'A' $ox $oy 16 1
  Rect 'A' $ox $oy 1 16
  Rect 'P' ($ox+1) ($oy+1) 15 15
  Rect 'A' ($ox+3) ($oy+3) 13 1
  Rect 'A' ($ox+3) ($oy+6) 13 1
  Rect 'A' ($ox+3) ($oy+3) 1 4
  Rect 'Q' ($ox+4) ($oy+4) 8 2
}
function Tile-DoorTopR($ox,$oy){         # door upper, right half
  Rect 'P' $ox $oy 16 16
  Rect 'A' ($ox+15) ($oy+1) 1 15
  Rect 'A' $ox ($oy+3) 13 1
  Rect 'A' $ox ($oy+6) 13 1
  Rect 'A' ($ox+12) ($oy+3) 1 4
}
function Tile-DoorMidL($ox,$oy){         # door middle, left half (big panel)
  Rect 'E' $ox $oy 16 16
  Rect 'A' $ox $oy 1 16
  Rect 'P' ($ox+1) $oy 15 16
  Rect 'A' ($ox+3) ($oy+2) 13 1
  Rect 'A' ($ox+3) ($oy+13) 13 1
  Rect 'A' ($ox+3) ($oy+2) 1 12
}
function Tile-DoorMidR($ox,$oy){         # door middle, right half + knob
  Rect 'P' $ox $oy 16 16
  Rect 'A' ($ox+15) $oy 1 16
  Rect 'A' $ox ($oy+2) 13 1
  Rect 'A' $ox ($oy+13) 13 1
  Rect 'A' ($ox+12) ($oy+2) 1 12
  Rect 'O' ($ox+5) ($oy+7) 2 2
  Rect 'M' ($ox+5) ($oy+7) 1 1
}
function Tile-DoorBottomL($ox,$oy){      # door bottom, left half
  Rect 'E' $ox $oy 16 16
  Rect 'A' $ox $oy 1 16
  Rect 'P' ($ox+1) $oy 15 14
  Rect 'A' ($ox+1) ($oy+14) 15 2
}
function Tile-DoorBottomR($ox,$oy){      # door bottom, right half
  Rect 'P' $ox $oy 16 16
  Rect 'A' ($ox+15) $oy 1 16
  Rect 'A' $ox ($oy+14) 16 2
}
function Tile-Breaker($ox,$oy){          # breaker box
  Rect 'E' $ox $oy 16 16
  Rect 'A' ($ox+3) ($oy+3) 10 10
  Rect 'H' ($ox+4) ($oy+4) 8 8
  Rect 'G' ($ox+4) ($oy+4) 8 1
  Rect 'A' ($ox+7) ($oy+5) 2 6
  Rect 'L' ($ox+5) ($oy+5) 2 2
  Rect 'J' ($ox+10) ($oy+6) 2 1
  Rect 'C' ($ox+5) ($oy+9) 6 1
}
function Tile-Locker($ox,$oy){           # courier locker grid
  Rect 'E' $ox $oy 16 16
  Rect 'A' ($ox+2) ($oy+2) 12 13
  Rect 'H' ($ox+3) ($oy+3) 10 11
  Rect 'A' ($ox+3) ($oy+7) 10 1
  Rect 'A' ($ox+3) ($oy+11) 10 1
  Rect 'A' ($ox+8) ($oy+3) 1 11
  Rect 'J' ($ox+6) ($oy+5) 1 1
  Rect 'J' ($ox+11) ($oy+5) 1 1
  Rect 'J' ($ox+6) ($oy+9) 1 1
  Rect 'J' ($ox+11) ($oy+9) 1 1
  Rect 'J' ($ox+6) ($oy+13) 1 1
  Rect 'J' ($ox+11) ($oy+13) 1 1
}

$tiles = @(
  'Tile-FloorA','Tile-FloorB','Tile-FloorC','Tile-Ceiling',
  'Tile-WallNoise','Tile-WallPeel','Tile-WallSkirt','Tile-AdRed',
  'Tile-AdWhite','Tile-Window',
  'Tile-DoorTopL','Tile-DoorTopR','Tile-DoorMidL','Tile-DoorMidR',
  'Tile-DoorBottomL','Tile-DoorBottomR',
  'Tile-Breaker','Tile-Locker'
)

# ---------------- 1) tile sheet (8 cols x 3 rows = 128x48) ----------------
$cols = 8; $rows = 3; $tw = 16
$sheet = New-Object System.Drawing.Bitmap (($cols*$tw), ($rows*$tw))
$script:g = [System.Drawing.Graphics]::FromImage($sheet)
$script:g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
Rect 'C' 0 0 ($cols*$tw) ($rows*$tw)
for ($i=0; $i -lt $tiles.Count; $i++){
  $cx = ($i % $cols) * $tw
  $cy = [int][Math]::Floor($i / $cols) * $tw
  & $tiles[$i] $cx $cy
}
$script:g.Dispose()
$sheet.Save($OutSheet, [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------- 2) 4x nearest preview of the sheet ----------------
$pv = New-Object System.Drawing.Bitmap (($cols*$tw*4), ($rows*$tw*4))
$pg = [System.Drawing.Graphics]::FromImage($pv)
$pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$pg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$pg.DrawImage($sheet, 0, 0, $pv.Width, $pv.Height)
$pg.Dispose()
$pv.Save($OutPreview, [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------- 3) assembled corridor sample (640x360) ----------------
$scene = New-Object System.Drawing.Bitmap (640, 360)
$script:g = [System.Drawing.Graphics]::FromImage($scene)
$script:g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
Rect 'D' 0 0 640 360
for ($row=0; $row -lt 23; $row++){
  for ($col=0; $col -lt 40; $col++){
    $x = $col*16; $y = $row*16
    if     ($row -le 1)  { Tile-Ceiling  $x $y }
    elseif ($row -eq 18) { Tile-WallSkirt $x $y }
    elseif ($row -ge 19) {
      switch ($col % 3) {
        0 { Tile-FloorA $x $y }
        1 { Tile-FloorB $x $y }
        default { Tile-FloorC $x $y }
      }
    } else { Tile-WallNoise $x $y }
  }
}
# decorations
Tile-AdRed   (5*16)  (6*16)
Tile-AdWhite (9*16)  (7*16)
Tile-AdRed   (14*16) (5*16)
Tile-AdWhite (24*16) (9*16)
Tile-Window  (12*16) (2*16)
Tile-Window  (30*16) (2*16)
Tile-Breaker (27*16) (13*16)
Tile-Locker  (7*16)  (17*16)
foreach ($dc in 20, 34) {          # 32px-wide doors (2 tiles each)
  Tile-DoorTopL    ($dc*16)     (14*16)
  Tile-DoorTopR    (($dc+1)*16) (14*16)
  Tile-DoorMidL    ($dc*16)     (15*16)
  Tile-DoorMidR    (($dc+1)*16) (15*16)
  Tile-DoorMidL    ($dc*16)     (16*16)
  Tile-DoorMidR    (($dc+1)*16) (16*16)
  Tile-DoorBottomL ($dc*16)     (17*16)
  Tile-DoorBottomR (($dc+1)*16) (17*16)
}
$script:g.Dispose()
$scene.Save($OutScene, [System.Drawing.Imaging.ImageFormat]::Png)

Write-Host ('sheet   -> ' + $OutSheet)
Write-Host ('preview -> ' + $OutPreview)
Write-Host ('scene   -> ' + $OutScene)
