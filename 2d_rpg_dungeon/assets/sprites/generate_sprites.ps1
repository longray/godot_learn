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

# ---- 躯干（v4：头肩段 y0-y9 + 手臂三态段 y10-y12 分离，上下行手臂随步态摆动）----
# 对侧协调：迈左脚=左手后摆（消失）右手前摆（保留），镜像同理
$torsoDownHead = @(
	"................",
	".....hhhhhh.....",
	"....hhhhhhhh....",
	"....hhHhhhhh....",
	"....hfffffFh....",
	"....hfDffDfh....",
	"....hffffffh....",
	".....fffffF.....",
	"....tttttttt....",
	"....tTtttttd...."
)
$torsoDownArmA = @(             # 迈左脚：左手后摆（消失），右手保留
	"....ttttttttf...",
	"....tttGGttf....",
	"....tttttttt...."
)
$torsoDownArmIdle = @(
	"...ftttttttf....",
	"...ftttGGttf....",
	"....tttttttt...."
)
$torsoDownArmB = @(             # 迈右脚：右手后摆（消失），左手保留
	"...ftttttttt....",
	"...ftttGGtt.....",
	"....tttttttt...."
)
$torsoUpHead = @(
	"................",
	".....hhhhhh.....",
	"....hhhhhhhh....",
	"....hhHhhhhh....",
	"....hhhhhhhh....",
	"....hhhhhhhh....",
	"....hhhhhhhh....",
	".....hhhhhh.....",
	"....tttttttt....",
	"....tTtttttd...."
)
$torsoUpArmA = @(               # 迈左脚：左手后摆，右手保留
	"....ttttttttf...",
	"....ttttttttf...",
	"....tttttttt...."
)
$torsoUpArmIdle = @(
	"...ftttttttf....",
	"...ftttttttf....",
	"....tttttttt...."
)
$torsoUpArmB = @(               # 迈右脚：右手后摆，左手保留
	"...ftttttttt....",
	"...ftttttttt....",
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
	@(($torsoDownHead + $torsoDownArmA + $legsA), `
		($torsoDownHead + $torsoDownArmIdle + $legsIdle), `
		($torsoDownHead + $torsoDownArmB + $legsB)),                      # 行0 = 下
	@(($torsoUpHead + $torsoUpArmA + $legsA), `
		($torsoUpHead + $torsoUpArmIdle + $legsIdle), `
		($torsoUpHead + $torsoUpArmB + $legsB)),                          # 行1 = 上
	@(($torsoSideHead + $torsoSideArmFwd + $sideLegsA), `
		($torsoSideHead + $torsoSideArmIdle + $sideLegsIdle), `
		($torsoSideHead + $torsoSideArmBack + $sideLegsB))                # 行2 = 侧面
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
# 钥匙：金钥匙三档渐变（亮金/金/暗金）+ 底部两档渐变阴影（悬浮道具感）
# L=亮金 G=金 g=暗金 S=深影(110) s=浅影(70)
# =========================================================
$keyMap = New-ColorMap `
	@("L", @(255, 240, 155)) @("G", @(245, 205, 70)) @("g", @(190, 155, 45)) `
	@("S", @(15, 20, 35, 110)) @("s", @(15, 20, 35, 70))
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
	"....sSSSSSs....."
)
$keyBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $keyBmp $key $keyMap 0 0 "key"
Save-AndVerify $keyBmp (Join-Path $outDir "key.png") $tile $tile
$keyBmp.Dispose()

# =========================================================
# 宝箱：木色四档 + 锁高光 + 底部两档渐变阴影
# N=亮木 W=木 w=中木 d=暗木 G=金边 L=锁亮 l=锁 S=深影 s=浅影
# =========================================================
$chestMap = New-ColorMap `
	@("N", @(178, 132, 84)) @("W", @(150, 105, 60)) @("w", @(120, 82, 45)) @("d", @(85, 58, 32)) `
	@("G", @(240, 200, 60)) @("L", @(240, 248, 255)) @("l", @(200, 212, 225)) `
	@("S", @(15, 20, 35, 110)) @("s", @(15, 20, 35, 70))
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
	"..sSSSSSSSSSs...",
	"...sSSSSSSs....."
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

# =========================================================
# 柔和阴影纹理：径向渐变椭圆（中心深 → 边缘平滑衰减到透明）
# 玩家/敌人共用（动态生物不画进素材——动画会缩放影子）
# =========================================================
$shadowBmp = New-Object System.Drawing.Bitmap $tile, $tile
$shCx = 8.0; $shCy = 12.0; $shRx = 5.5; $shRy = 2.5; $shMaxA = 200
for ($y = 0; $y -lt $tile; $y++) {
	for ($x = 0; $x -lt $tile; $x++) {
		$dx = ($x - $shCx) / $shRx
		$dy = ($y - $shCy) / $shRy
		$d = [math]::Sqrt($dx * $dx + $dy * $dy)
		if ($d -lt 1.0) {
			$a = [int]($shMaxA * (1.0 - $d))   # 线性衰减：中心 255 → 边缘 0
			$shadowBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, 10, 15, 30))
		}
	}
}
Save-AndVerify $shadowBmp (Join-Path $outDir "shadow.png") $tile $tile
$shadowBmp.Dispose()

# =========================================================
# 生命值 UI：心形图标（满心=亮红渐变 / 空心=暗灰空心）
# R=主红 r=暗红 L=高光 E=空框 e=空底
# =========================================================
$heartFullMap = New-ColorMap `
	@("R", @(220, 60, 70)) @("r", @(160, 35, 50)) @("L", @(255, 150, 160))
$heartFull = @(
	"................",
	"................",
	"................",
	".RRRR..RRRR.....",
	"RLRRRRRRRRRr....",
	"RLRRRRRRRRr.....",
	".RRRRRRRRr......",
	"..RRRRRRr.......",
	"...RRRRr........",
	"....RRr.........",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................"
)
$heartEmptyMap = New-ColorMap `
	@("E", @(90, 80, 90)) @("e", @(50, 44, 54))
$heartEmpty = @(
	"................",
	"................",
	"................",
	".EEEE..EEEE.....",
	"EEeeeEEeeeeE....",
	"EEeeeEEeeeeE....",
	".EEeEEEEEee.....",
	"..EEeEEEEe......",
	"...EEEEEe.......",
	"....EEEe........",
	"................",
	"................",
	"................",
	"................",
	"................",
	"................"
)

$outDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$heartFullBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $heartFullBmp $heartFull $heartFullMap 0 0 "heart_full"
Save-AndVerify $heartFullBmp (Join-Path $outDir "heart_full.png") $tile $tile
$heartFullBmp.Dispose()

$heartEmptyBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $heartEmptyBmp $heartEmpty $heartEmptyMap 0 0 "heart_empty"
Save-AndVerify $heartEmptyBmp (Join-Path $outDir "heart_empty.png") $tile $tile
$heartEmptyBmp.Dispose()

# =========================================================
# 掉落物：金币（大金圆+内圈）与红药水（RPG 血药共识：红=回血）
# G=主金 L=亮金 g=暗金 | R=红药 W=高光 C=软木塞 r=暗红
# =========================================================
$goldMap = New-ColorMap `
	@("L", @(255, 242, 160)) @("G", @(245, 205, 70)) @("g", @(185, 148, 40))
$goldCoin = @(
	"................",
	"................",
	"................",
	"....LLLLLL......",
	"...LGGGGGGL.....",
	"..LGGgggGGGL....",
	".LGGgLLLgGGGL...",
	".LGgLGGGgLgGL...",
	".LGgLGGGgLgGL...",
	".LGGgLLLgGGGL...",
	"..LGGgggGGGL....",
	"...LGGGGGGL.....",
	"....LLLLLL......",
	"................",
	"................",
	"................"
)
$potionMap = New-ColorMap `
	@("R", @(225, 55, 75)) @("W", @(255, 170, 180)) @("C", @(160, 115, 70)) @("r", @(160, 30, 50))
$potion = @(
	"................",
	"................",
	"......CC........",
	"......CC........",
	".....rrrr.......",
	"....rRRRRr......",
	"...rRWRRRRr.....",
	"..rRWRRRRRRr....",
	"..rWRRRRRRRr....",
	"..rRRRRRRRRr....",
	"..rRRRRRRRRr....",
	"...rRRRRRRr.....",
	"....rrrrrr......",
	"................",
	"................",
	"................"
)

$goldBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $goldBmp $goldCoin $goldMap 0 0 "gold"
Save-AndVerify $goldBmp (Join-Path $outDir "gold.png") $tile $tile
$goldBmp.Dispose()

$potionBmp = New-Object System.Drawing.Bitmap $tile, $tile
Draw-Frame $potionBmp $potion $potionMap 0 0 "potion"
Save-AndVerify $potionBmp (Join-Path $outDir "potion.png") $tile $tile
$potionBmp.Dispose()

# 旧单帧 player.png 已被 player_sheet.png 取代（down-idle 帧），删除避免混淆
$oldPlayer = Join-Path $outDir "player.png"
if (Test-Path $oldPlayer) {
	Remove-Item $oldPlayer -Force
	Remove-Item "$oldPlayer.import" -Force -ErrorAction SilentlyContinue
	Write-Output "removed obsolete: player.png"
}
