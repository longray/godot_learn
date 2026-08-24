# generate_tiles_v2.ps1 —— 雪原冰窟主题瓦片图集（用于区分手工 TileSet vs .tres TileSet）
# 输出: dungeon_tiles_ice.png（64x16，横向 4 个 16x16 瓦片：冰地板/冰墙/入口/出口）
# 不同种子 → 不同噪点分布；不同调色板 → 完全不同的视觉风格
Add-Type -AssemblyName System.Drawing

$tile = 16
$bmp = New-Object System.Drawing.Bitmap ($tile * 4), $tile
$script:seed = 777001

function Get-Rand {
	$script:seed = ($script:seed * 1103515245 + 12345) % 2147483648
	return $script:seed
}

function Set-Px([int]$x, [int]$y, [int[]]$c) {
	$bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c[0], $c[1], $c[2]))
}

# ---------- 瓦片 0（x 0..15）：冰地板——淡蓝冰面 + 横向裂纹 ----------
$fBase = @(196, 216, 232); $fD1 = @(180, 202, 222); $fL = @(214, 232, 244)
$crack = @(148, 176, 202)
for ($y = 0; $y -lt $tile; $y++) {
	for ($x = 0; $x -lt $tile; $x++) {
		$r = (Get-Rand) % 100
		$c = $fBase
		if ($r -lt 25) { $c = $fD1 } elseif ($r -lt 40) { $c = $fL }
		# 三条错位横向裂纹（冰面特征）
		if (($y -eq 3 -and (($x + 2) % 7) -lt 3) -or `
			($y -eq 9 -and (($x + 5) % 9) -lt 4) -or `
			($y -eq 13 -and (($x + 1) % 6) -lt 2)) { $c = $crack }
		Set-Px $x $y $c
	}
}

# ---------- 瓦片 1（x 16..31）：冰墙——深蓝石块 + 大块无缝 ----------
$rock = @(58, 78, 106); $rHi = @(72, 94, 124); $rLo = @(46, 62, 86); $rSeam = @(34, 46, 66)
for ($y = 0; $y -lt $tile; $y++) {
	for ($lx = 0; $lx -lt $tile; $lx++) {
		$x = 16 + $lx
		$c = $rock
		$row = [math]::Floor($y / 8)
		if (($y % 8) -eq 7) {
			$c = $rSeam                                    # 8 行一条横缝（比砖墙块更大）
		} else {
			$off = 0; if (($row % 2) -eq 1) { $off = 5 }
			if (((($lx + $off) % 10)) -eq 9) { $c = $rSeam }  # 竖缝更稀
			else {
				$r = (Get-Rand) % 100
				if ($r -lt 22) { $c = $rHi } elseif ($r -lt 42) { $c = $rLo }
			}
		}
		Set-Px $x $y $c
	}
}

# ---------- 瓦片 2（x 32..47）：入口——深蓝底 + 黄色向下箭头（对比旧版绿色） ----------
$eBg = @(24, 40, 72); $eBgD = @(20, 34, 62); $eBd = @(250, 204, 21); $eAr = @(254, 240, 138)
for ($y = 0; $y -lt $tile; $y++) {
	for ($lx = 0; $lx -lt $tile; $lx++) {
		$x = 32 + $lx
		$c = $eBg
		$r = (Get-Rand) % 100
		if ($r -lt 30) { $c = $eBgD }
		if ($lx -eq 0 -or $lx -eq 15 -or $y -eq 0 -or $y -eq 15) { $c = $eBd }
		$inShaft = ($lx -ge 6 -and $lx -le 9 -and $y -ge 3 -and $y -le 7)
		$inHead = ($y -eq 8 -and $lx -ge 4 -and $lx -le 11) -or `
			($y -eq 9 -and $lx -ge 5 -and $lx -le 10) -or `
			($y -eq 10 -and $lx -ge 6 -and $lx -le 9) -or `
			($y -eq 11 -and $lx -ge 7 -and $lx -le 8)
		if ($inShaft -or $inHead) { $c = $eAr }
		Set-Px $x $y $c
	}
}

# ---------- 瓦片 3（x 48..63）：出口——深蓝底 + 紫色向上箭头（对比旧版红色） ----------
$xBg = @(40, 24, 72); $xBgD = @(34, 20, 62); $xBd = @(192, 132, 252); $xAr = (233, 213, 255) -as [int[]]
$xAr = [int[]]@(233, 213, 255)
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
			($y -eq 6 -and $lx -ge 4 -and $lx -le 11)
		$inShaft = ($lx -ge 6 -and $lx -le 9 -and $y -ge 7 -and $y -le 12)
		if ($inShaft -or $inHead) { $c = $xAr }
		Set-Px $x $y $c
	}
}

# ---------- 保存 + 验证读回 ----------
$outDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$png = Join-Path $outDir "dungeon_tiles_ice.png"
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
