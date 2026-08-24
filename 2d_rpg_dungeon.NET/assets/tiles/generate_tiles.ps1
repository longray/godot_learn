# generate_tiles.ps1 —— 程序化生成地牢瓦片图集（作业 5 素材）
# 输出: dungeon_tiles.png（64x16，横向 4 个 16x16 瓦片：地板/墙壁/入口/出口）
# 固定 LCG 种子 → 逐位可复现；改调色板或种子即可批量换皮
Add-Type -AssemblyName System.Drawing

$tile = 16
$bmp = New-Object System.Drawing.Bitmap ($tile * 4), $tile
$script:seed = 20260824

function Get-Rand {
	$script:seed = ($script:seed * 1103515245 + 12345) % 2147483648
	return $script:seed
}

function Set-Px([int]$x, [int]$y, [int[]]$c) {
	$bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c[0], $c[1], $c[2]))
}

# ---------- 瓦片 0（x 0..15）：地板——石板 + 噪点 + 田字缝 ----------
$fBase = @(138, 127, 106); $fD1 = @(123, 112, 94); $fD2 = @(112, 102, 86)
$fL = @(150, 139, 117); $seam = @(98, 89, 75)
for ($y = 0; $y -lt $tile; $y++) {
	for ($x = 0; $x -lt $tile; $x++) {
		$r = (Get-Rand) % 100
		$c = $fBase
		if ($r -lt 28) { $c = $fD1 } elseif ($r -lt 48) { $c = $fD2 } elseif ($r -lt 58) { $c = $fL }
		if (($x % 8) -eq 0 -or ($y % 8) -eq 0) { $c = $seam }  # 田字缝
		Set-Px $x $y $c
	}
}

# ---------- 瓦片 1（x 16..31）：墙壁——交错砖墙 ----------
$brick = @(72, 72, 86); $bHi = @(84, 84, 100); $bLo = @(60, 60, 72); $mortar = @(42, 42, 54)
for ($y = 0; $y -lt $tile; $y++) {
	for ($lx = 0; $lx -lt $tile; $lx++) {
		$x = 16 + $lx
		$row = [math]::Floor($y / 4)
		$c = $brick
		if (($y % 4) -eq 3) {
			$c = $mortar                                   # 横向砖缝（每 4 行）
		} else {
			$off = 0; if (($row % 2) -eq 1) { $off = 4 }   # 奇数行错位
			if (((($lx + $off) % 8)) -eq 7) { $c = $mortar }  # 竖向砖缝
			else {
				$r = (Get-Rand) % 100
				if ($r -lt 20) { $c = $bHi } elseif ($r -lt 40) { $c = $bLo }
			}
		}
		Set-Px $x $y $c
	}
}

# ---------- 瓦片 2（x 32..47）：入口——绿底向下箭头 ----------
$eBg = @(30, 86, 49); $eBgD = @(26, 74, 42); $eBd = @(74, 222, 128); $eAr = @(134, 239, 172)
for ($y = 0; $y -lt $tile; $y++) {
	for ($lx = 0; $lx -lt $tile; $lx++) {
		$x = 32 + $lx
		$c = $eBg
		$r = (Get-Rand) % 100
		if ($r -lt 30) { $c = $eBgD }
		if ($lx -eq 0 -or $lx -eq 15 -or $y -eq 0 -or $y -eq 15) { $c = $eBd }  # 边框
		$inShaft = ($lx -ge 6 -and $lx -le 9 -and $y -ge 3 -and $y -le 7)        # 箭杆
		$inHead = ($y -eq 8 -and $lx -ge 4 -and $lx -le 11) -or `
			($y -eq 9 -and $lx -ge 5 -and $lx -le 10) -or `
			($y -eq 10 -and $lx -ge 6 -and $lx -le 9) -or `
			($y -eq 11 -and $lx -ge 7 -and $lx -le 8)                             # 三角箭头
		if ($inShaft -or $inHead) { $c = $eAr }
		Set-Px $x $y $c
	}
}

# ---------- 瓦片 3（x 48..63）：出口——红底向上箭头 ----------
$xBg = @(86, 30, 30); $xBgD = @(74, 26, 26); $xBd = @(248, 113, 113); $xAr = @(254, 202, 202)
for ($y = 0; $y -lt $tile; $y++) {
	for ($lx = 0; $lx -lt $tile; $lx++) {
		$x = 48 + $lx
		$c = $xBg
		$r = (Get-Rand) % 100
		if ($r -lt 30) { $c = $xBgD }
		if ($lx -eq 0 -or $lx -eq 15 -or $y -eq 0 -or $y -eq 15) { $c = $xBd }
		$inHead = ($y -eq 3 -and $lx -ge 7 -and $lx -le 8) -or `
			($y -eq 4 -and $lx -ge 6 -and $lx -le 9) -or `
			($y -eq 5 -and $lx -ge 5 -and $lx -le 10) -or `
			($y -eq 6 -and $lx -ge 4 -and $lx -le 11)                             # 三角朝上
		$inShaft = ($lx -ge 6 -and $lx -le 9 -and $y -ge 7 -and $y -le 12)        # 箭杆在下
		if ($inShaft -or $inHead) { $c = $xAr }
		Set-Px $x $y $c
	}
}

# ---------- 保存 + 验证读回 ----------
$outDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$png = Join-Path $outDir "dungeon_tiles.png"
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$check = New-Object System.Drawing.Bitmap $png
Write-Output "saved: $png"
Write-Output "size: $($check.Width)x$($check.Height)"
Write-Output "floor(1,1) RGB: $($check.GetPixel(1,1).R),$($check.GetPixel(1,1).G),$($check.GetPixel(1,1).B)"
Write-Output "wall(20,1)  RGB: $($check.GetPixel(20,1).R),$($check.GetPixel(20,1).G),$($check.GetPixel(20,1).B)"
Write-Output "entry(40,5) RGB: $($check.GetPixel(40,5).R),$($check.GetPixel(40,5).G),$($check.GetPixel(40,5).B)"
Write-Output "exit(56,4)  RGB: $($check.GetPixel(56,4).R),$($check.GetPixel(56,4).G),$($check.GetPixel(56,4).B)"
$check.Dispose()
