# generate_sprites.ps1 —— 角色/道具像素素材（16x16，透明背景）
# v2：四向行走 spritesheet + 全素材立体感（定光源明暗/底部阴影/多档渐变）
# 输出: player_sheet.png (48x64: 行0=下 行1=上 行2=侧面, 列=迈A/站立/迈B)
#       key.png / chest.png / monster.png（含画入素材的底部阴影）
Add-Type -AssemblyName System.Drawing

$tile = 16

# ---------- 工具 ----------
# PowerShell 哈希表键不区分大小写（W/w 会撞键），用 .NET Dictionary（区分大小写）
# 颜色值支持 3 元素 [r,g,b]（不透明）或 4 元素 [r,g,b,a]（半透明）
function New-ColorMap {
	$d = [System.Collections.Generic.Dictionary[string, object]]::new()
	foreach ($kv in $args) { $d[$kv[0]] = $kv[1] }
	return $d
}

function Set-Px($bmp, [int]$x, [int]$y, $c) {
	if ($c.Count -eq 3) {
		$bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
	} else {
		$bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c[3], $c[0], $c[1], $c[2]))
	}
}

# 画一帧到大图的 (ox,oy) 偏移处
function Draw-Frame($bmp, [string[]]$rows, $map, [int]$ox, [int]$oy, [string]$name) {
	if ($rows.Count -ne $tile) { throw "$name 行数错误: $($rows.Count)" }
	for ($y = 0; $y -lt $tile; $y++) {
		$row = $rows[$y]
		if ($row.Length -ne $tile) { throw "$name 第 $y 行长度错误: $($row.Length) -> $row" }
		for ($x = 0; $x -lt $tile; $x++) {
			$ch = $row[$x].ToString()
			if ($ch -ne ".") {
				$c = $map[$ch]
				if ($null -eq $c) { throw "$name 未知颜色字符: $ch" }
				Set-Px $bmp ($ox + $x) ($oy + $y) $c
			}
		}
	}
}

function Save-AndVerify($bmp, [string]$outPath, [int]$w, [int]$h) {
	$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
	$check = New-Object System.Drawing.Bitmap $outPath
	$ok = ($check.Width -eq $w -and $check.Height -eq $h)
	$cornerA = $check.GetPixel(0, 0).A
	$check.Dispose()
	Write-Output ("saved: {0}  size: {1}x{2}  ok={3} cornerA={4}" -f $outPath, $w, $h, $ok, $cornerA)
}

# =========================================================
# 玩家：蓝衣小英雄（立体感：左上高光，右侧暗列；光从左上来）
# h=头发 H=发高光 f=肤色 F=肤暗 D=眼 t=蓝衣 T=衣亮 d=衣暗
# G=金扣 p=裤 P=裤暗 b=靴 B=靴暗
# =========================================================
$playerMap = New-ColorMap `
	@("h", @(58, 60, 66)) @("H", @(84, 86, 95)) `
	@("f", @(232, 190, 150)) @("F", @(210, 168, 128)) @("D", @(40, 40, 50)) `
	@("t", @(58, 108, 190)) @("T", @(90, 140, 225)) @("d", @(40, 80, 155)) `
	@("G", @(240, 200, 60)) `
	@("p", @(60, 70, 90)) @("P", @(45, 54, 70)) `
	@("b", @(110, 75, 45)) @("B", @(85, 58, 35))

# ---- 躯干（y0-y12，13 行；v3 瘦身：头 8 宽、躯干 9-10 宽）----
$torsoDown = @(
	"................",
	".....hhhhhh.....",
	"....hhhhhhhh....",
	"....hhHhhhhh....",
	"....hfffffFh....",
	"....hfDffDfh....",
	"....hffffffh....",
	".....fffffF.....",
	"....tttttttt....",
	"....tTtttttd....",
	"...ftttttttf....",
	"...ftttGGttf....",
	"....tttttttt...."
)
$torsoUp = @(
	"................",
	".....hhhhhh.....",
	"....hhhhhhhh....",
	"....hhHhhhhh....",
	"....hhhhhhhh....",
	"....hhhhhhhh....",
	"....hhhhhhhh....",
	".....hhhhhh.....",
	"....tttttttt....",
	"....tTtttttd....",
	"...ftttttttf....",
	"...ftttttttf....",
	"....tttttttt...."
)
# 侧面（朝右）：y10 手臂行分三态（前摆/垂/后摆），其余共用
$torsoSideHead = @(
	"................",
	".....hhhhhh.....",
	"....hhhhhhhh....",
	"....hhhHhhhh....",
	"....hhhfffff....",
	"....hhhffDff....",
	"....hhhfffff....",
	".....hhffff.....",
	"....ttttttt.....",
	"....tTttttt....."
)
$torsoSideArmFwd = @(            # stepA：手臂前摆
	"..ftttttt.......",
	"...ftttGt.......",
	"....ttttt......."
)
$torsoSideArmIdle = @(           # idle：手臂垂
	"...ftttttt......",
	"...ftttGt.......",
	"....ttttt......."
)
$torsoSideArmBack = @(           # stepB：手臂后摆
	"....fttttt......",
	"...ftttGt.......",
	"....ttttt......."
)

# ---- 腿部（y13-y15，3 行；v3：上下行迈步 = 靴子外移 + 抬起，动作加大）----
$legsIdle = @(
	".....pp..PP.....",
	".....bb..BB.....",
	"....bbb..BBB...."
)
$legsA = @(                       # 迈左脚：左靴跨出落地，右靴抬起（消失）——对比最大化
	".....pp..PP.....",
	"....bbb..BB.....",
	"...bbb.........."
)
$legsB = @(                       # 迈右脚：右靴跨出落地，左靴抬起
	".....pp..PP.....",
	".....bb..BBB....",
	"..........bbb..."
)
$sideLegsIdle = @(
	".....pp.PP......",
	".....bb.BB......",
	"....bbb.BBB....."
)
$sideLegsA = @(                   # 前脚前迈（朝右：前=右）
	"....pp..PP......",
	"...bb....BB.....",
	"..bbb....BBB...."
)
$sideLegsB = @(
	".....pp.PP......",
	"....bb..BB......",
	"....bbb.BBB....."
)

# ---- 拼 12 帧 ----
$sheet = New-Object System.Drawing.Bitmap ($tile * 3), ($tile * 4)
$frames = @(
	@(($torsoDown + $legsA), ($torsoDown + $legsIdle), ($torsoDown + $legsB)),      # 行0 = 下
	@(($torsoUp + $legsA), ($torsoUp + $legsIdle), ($torsoUp + $legsB)),            # 行1 = 上
	@(($torsoSideHead + $torsoSideArmFwd + $sideLegsA), `
		($torsoSideHead + $torsoSideArmIdle + $sideLegsIdle), `
		($torsoSideHead + $torsoSideArmBack + $sideLegsB))                          # 行2 = 侧面
)
for ($row = 0; $row -lt 3; $row++) {
	for ($col = 0; $col -lt 3; $col++) {
		Draw-Frame $sheet $frames[$row][$col] $playerMap ($col * $tile) ($row * $tile) "player r$row c$col"
	}
}

$outDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Save-AndVerify $sheet (Join-Path $outDir "player_sheet.png") ($tile * 3) ($tile * 4)
$sheet.Dispose()

# =========================================================
# 钥匙：金钥匙三档渐变（亮金/金/暗金）+ 底部半透明阴影（悬浮道具感）
# L=亮金 G=金 g=暗金 S=阴影(半透明)
# =========================================================
$keyMap = New-ColorMap `
	@("L", @(255, 240, 155)) @("G", @(245, 205, 70)) @("g", @(190, 155, 45)) `
	@("S", @(15, 20, 35, 110))
$key = @(
	"................",
	".....LGGGg......",
	"....LG....Gg....",
	"....L......g....",
	"....L......g....",
	"....LG....Gg....",
	".....LGGGg......",
	".......LGg......",
	".......LGg......",
	".......LGg......",
	".......LGg......",
	".......LGg......",
	".......LGg......",
	"......LGgGg.....",
	"......Lg.Lg.....",
	"...SSSSSSSSSS..."
)
$keyBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $keyBmp $key $keyMap 0 0 "key"
Save-AndVerify $keyBmp (Join-Path $outDir "key.png") $tile $tile
$keyBmp.Dispose()

# =========================================================
# 宝箱：木色四档 + 锁高光 + 底部半透明阴影
# N=亮木 W=木 w=中木 d=暗木 G=金边 L=锁亮 l=锁 S=阴影
# =========================================================
$chestMap = New-ColorMap `
	@("N", @(178, 132, 84)) @("W", @(150, 105, 60)) @("w", @(120, 82, 45)) @("d", @(85, 58, 32)) `
	@("G", @(240, 200, 60)) @("L", @(240, 248, 255)) @("l", @(200, 212, 225)) `
	@("S", @(15, 20, 35, 110))
$chest = @(
	"................",
	"....NWWWWWW.....",
	"...NWWwwwwwW....",
	"..NWWwwwwwwwW...",
	"..NWwwwwwwwwW...",
	"..NWwwwwwwwwW...",
	".GGGGGGGGGGGGG..",
	".GGGGGLlGGGGGG..",
	".wwwwGLlLwwwww..",
	".wwwwwGGGwwwww..",
	".WwwwwwwwwwwwW..",
	".WwwwwwwwwwwwW..",
	".WWwwwwwwwwwWW..",
	".ddddddddddddd..",
	"..SSSSSSSSSSS...",
	"...SSSSSSSS....."
)
$chestBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $chestBmp $chest $chestMap 0 0 "chest"
Save-AndVerify $chestBmp (Join-Path $outDir "chest.png") $tile $tile
$chestBmp.Dispose()

# =========================================================
# 怪物：紫史莱姆三档渐变（影子不画进素材——呼吸动画会缩放它，
# 用 enemy.tscn 的独立 Shadow 节点，动画时影子稳定）
# P=亮紫 p=紫 q=暗紫 W=眼白 D=瞳
# =========================================================
$monsterMap = New-ColorMap `
	@("P", @(178, 110, 215)) @("p", @(150, 80, 190)) @("q", @(110, 55, 145)) `
	@("W", @(245, 245, 250)) @("D", @(40, 30, 60))
$monster = @(
	"................",
	"................",
	"......PPPP......",
	"....PPpppPPp....",
	"...PPpppppppq...",
	"..PPpppppppppq..",
	"..pWWppppppWWp..",
	"..pWDppppppDWq..",
	".Ppppppppppppq..",
	".PppppDDDDpppq..",
	".Ppppppppppppq..",
	".pppppppppppqq..",
	".qpppppppppqqq..",
	".qqqqqqqqqqqqq..",
	"................",
	"................"
)
$monsterBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $monsterBmp $monster $monsterMap 0 0 "monster"
Save-AndVerify $monsterBmp (Join-Path $outDir "monster.png") $tile $tile
$monsterBmp.Dispose()

# 旧单帧 player.png 已被 player_sheet.png 取代（down-idle 帧），删除避免混淆
$oldPlayer = Join-Path $outDir "player.png"
if (Test-Path $oldPlayer) {
	Remove-Item $oldPlayer -Force
	Remove-Item "$oldPlayer.import" -Force -ErrorAction SilentlyContinue
	Write-Output "removed obsolete: player.png"
}
