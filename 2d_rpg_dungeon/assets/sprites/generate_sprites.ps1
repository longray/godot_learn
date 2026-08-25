# generate_sprites.ps1 —— 角色/道具像素素材（16x16，透明背景）
# 输出: player.png / key.png / chest.png / monster.png
# 设计：玩家=绿衣小英雄（钢盔+肤色脸）、钥匙=金钥匙（环+齿）、
#       宝箱=木箱金边银锁、怪物=紫史莱姆（白眼瞳+嘴）
Add-Type -AssemblyName System.Drawing

$tile = 16

# ---------- 工具 ----------
# PowerShell 哈希表键不区分大小写（W/w 会撞键），用 .NET Dictionary（区分大小写）
function New-ColorMap {
	$d = [System.Collections.Generic.Dictionary[string, object]]::new()
	foreach ($kv in $args) { $d[$kv[0]] = $kv[1] }
	return $d
}

function Convert-Sprite([string[]]$rows, $map, [string]$outPath) {
	if ($rows.Count -ne $tile) { throw "$outPath 行数错误: $($rows.Count)" }
	$bmp = New-Object System.Drawing.Bitmap $tile, $tile
	for ($y = 0; $y -lt $tile; $y++) {
		$row = $rows[$y]
		if ($row.Length -ne $tile) { throw "$outPath 第 $y 行长度错误: $($row.Length) -> $row" }
		for ($x = 0; $x -lt $tile; $x++) {
			$ch = $row[$x].ToString()
			if ($ch -ne ".") {
				$c = $map[$ch]
				if ($null -eq $c) { throw "$outPath 未知颜色字符: $ch" }
				$bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
			}
		}
	}
	$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
	$bmp.Dispose()

	# 读回验证：尺寸 + 角落透明 + 中心不透明
	$check = New-Object System.Drawing.Bitmap $outPath
	$cornerAlpha = $check.GetPixel(0, 0).A
	$centerAlpha = $check.GetPixel(8, 8).A
	$check.Dispose()
	Write-Output ("saved: {0}  size: {1}x{2}  cornerA={3} centerA={4}" -f `
		$outPath, $tile, $tile, $cornerAlpha, $centerAlpha)
}

# ---------- 玩家：蓝衣小英雄（黑灰头发 + 肤色脸） ----------
# h=头发(黑偏灰) f=肤色 D=眼 t=蓝衣 G=金扣 p=裤 b=靴
$playerMap = New-ColorMap `
	@("h", @(58, 60, 66)) @("f", @(232, 190, 150)) @("D", @(40, 40, 50)) `
	@("t", @(58, 108, 190)) @("G", @(240, 200, 60)) `
	@("p", @(60, 70, 90)) @("b", @(110, 75, 45))
$player = @(
	"................",
	"....hhhhhhhh....",
	"...hhhhhhhhhh...",
	"...hhhhhhhhhh...",
	"...hffffffffh...",
	"...hfDffffDfh...",
	"...hffffffffh...",
	"....ffffffff....",
	"...tttttttttt...",
	"..tttttttttttt..",
	"..fttttttttttf..",
	"..fttttGGttttf..",
	"...tttttttttt...",
	"....pp....pp....",
	"....bb....bb....",
	"...bbb....bbb..."
)

# ---------- 钥匙：金钥匙（环+杆+齿） ----------
$keyMap = New-ColorMap @("G", @(255, 215, 80))
$key = @(
	"................",
	".....GGGGGG.....",
	"....GG....GG....",
	"....G......G....",
	"....G......G....",
	"....GG....GG....",
	".....GGGGGG.....",
	".......GG.......",
	".......GG.......",
	".......GG.......",
	".......GG.......",
	".......GG.......",
	".......GG.......",
	"......GGG.......",
	"......GG........",
	"................"
)

# ---------- 宝箱：木箱金边银锁 ----------
# W=亮木 w=木 d=暗木 G=金 l=银锁
$chestMap = New-ColorMap `
	@("W", @(150, 105, 60)) @("w", @(120, 82, 45)) @("d", @(85, 58, 32)) `
	@("G", @(240, 200, 60)) @("l", @(220, 230, 240))
$chest = @(
	"................",
	"....WWWWWWWW....",
	"...WWwwwwwwWW...",
	"..WWwwwwwwwwWW..",
	"..WWwwwwwwwwWW..",
	"..WWwwwwwwwwWW..",
	".GGGGGGGGGGGGGG.",
	".GGGGGGllGGGGGG.",
	".wwwwwGllGwwwww.",
	".wwwwwGGGGwwwww.",
	".wwwwwwwwwwwwww.",
	".wwwwwwwwwwwwww.",
	".WWwwwwwwwwwwWW.",
	".dddddddddddddd.",
	"................",
	"................"
)

# ---------- 怪物：紫史莱姆 ----------
# p=紫 P=暗紫 W=眼白 D=瞳
$monsterMap = New-ColorMap `
	@("p", @(150, 80, 190)) @("P", @(110, 55, 145)) `
	@("W", @(245, 245, 250)) @("D", @(40, 30, 60))
$monster = @(
	"................",
	"................",
	"......pppp......",
	"....pppppppp....",
	"...pppppppppp...",
	"..pppppppppppp..",
	"..pWWppppppWWp..",
	"..pWDppppppDWp..",
	".pppppppppppppp.",
	".pppppDDDDppppp.",
	".pppppppppppppp.",
	".pppppppppppppp.",
	".PppppppppppppP.",
	".PPPPPPPPPPPPPP.",
	"................",
	"................"
)

# ---------- 输出 ----------
$outDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Convert-Sprite $player  $playerMap  (Join-Path $outDir "player.png")
Convert-Sprite $key     $keyMap     (Join-Path $outDir "key.png")
Convert-Sprite $chest   $chestMap   (Join-Path $outDir "chest.png")
Convert-Sprite $monster $monsterMap (Join-Path $outDir "monster.png")
