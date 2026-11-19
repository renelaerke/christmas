# Nordpol kontrolcenter: a live terminal dashboard for JuleHygge (used for the README pictures).
# Start the app with JULE_DEBUG=1 so it writes %TEMP%\julehygge-debug.log, then run this in Windows Terminal
# (about 96x26 characters):  powershell -ExecutionPolicy Bypass -File tools\nordpol.ps1
# It follows the log for events and samples the app's CPU use. JULE_DATE=yyyy-MM-dd moves the countdown.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$e = [char]27
function C($r, $g, $b) { "$e[38;2;${r};${g};${b}m" }
$R = "$e[0m"; $B = "$e[1m"; $D = "$e[2m"
$red = C 235 70 70; $grn = C 90 200 120; $gold = C 250 205 90; $ice = C 150 210 255; $wht = C 235 240 250; $gry = C 120 130 150; $pink = C 255 120 170

$log = Join-Path $env:TEMP 'julehygge-debug.log'
$cpuHist = New-Object System.Collections.Generic.List[double]
$events = New-Object System.Collections.Generic.List[string]
$stats = @{ gifts = 0; breaks = 0; plows = 0; cross = 0 }
$fps = '--'
$pos = 0
if (Test-Path $log) { $pos = (Get-Item $log).Length }
$prevCpu = $null; $prevT = [DateTime]::Now
$cores = [Environment]::ProcessorCount
$spark = ' ▁▂▃▄▅▆▇▇'
$frame = 0
$W = 92

function Base-Date {
    $d = [DateTime]::Now
    if ($env:JULE_DATE) { $j = [DateTime]::ParseExact($env:JULE_DATE, 'yyyy-MM-dd', $null); $d = $j.Date + $d.TimeOfDay }
    $d
}

function Add-Event($icon, $color, $text) {
    $events.Insert(0, ("{0}{1}{2}  {3}{4}{5}" -f $gry, (Get-Date -Format 'HH:mm:ss'), $R, $icon, " $color$text", $R))
    while ($events.Count -gt 9) { $events.RemoveAt($events.Count - 1) }
}

function Read-Log {
    if (-not (Test-Path $log)) { return }
    $len = (Get-Item $log).Length
    if ($len -lt $script:pos) { $script:pos = 0 }
    if ($len -eq $script:pos) { return }
    $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
    $fs.Seek($script:pos, 'Begin') | Out-Null
    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
    $text = $sr.ReadToEnd(); $sr.Close()
    $script:pos = $len
    foreach ($line in $text -split "`n") {
        $l = $line.Trim()
        if ($l -match 'fps ([\d.]+)') { $script:fps = $Matches[1] }
        elseif ($l -match 'gave (byttet|overrakt)') { $stats.gifts++; Add-Event '🎁' $pink ("To nisser mødtes - gave " + $Matches[1]) }
        elseif ($l -match 'snow broke off.*\((\d+) columns') { $stats.breaks++; Add-Event '❄ ' $ice ("Sne skred ned fra et vindue (" + $Matches[1] + " kolonner)") }
        elseif ($l -match 'plow start') { $stats.plows++; Add-Event '🚜' $gold 'Sneploven er rykket ud' }
        elseif ($l -match 'plow done') { Add-Event '✔ ' $grn 'Proceslinjen er ryddet' }
        elseif ($l -match 'nisse crossed') { $stats.cross++; Add-Event '🧝' $grn 'En nisse gik over til en anden skærm' }
        elseif ($l -match 'gone: (\d+) clumps') { Add-Event '🌨' $ice ("Vindue lukket - " + $Matches[1] + " sneklumper falder") }
        elseif ($l -match 'audio started') { Add-Event '🔔' $gold 'Bjælderne ringer' }
    }
}

function Sample-Cpu {
    $p = Get-Process JuleHygge
    $now = [DateTime]::Now
    if (-not $p) { return 0 }

    $total = [TimeSpan]::FromTicks([long]($p | ForEach-Object { $_.TotalProcessorTime.Ticks } | Measure-Object -Sum).Sum)
    $v = 0
    if ($script:prevCpu -ne $null) {
        $dt = ($now - $script:prevT).TotalSeconds
        if ($dt -gt 0) { $v = ($total - $script:prevCpu).TotalSeconds / $dt / $cores * 100 }
    }
    $script:prevCpu = $total; $script:prevT = $now
    [Math]::Max(0, $v)
}

function Bar($v, $max, $width, $color) {
    $n = [int][Math]::Round([Math]::Min(1, $v / $max) * $width)
    $color + ('━' * $n) + $gry + ('─' * ($width - $n)) + $R
}

function Tree($f) {
    $lights = @($red, $gold, $ice, $pink, $grn)
    $rows = @('    ★    ', '   /o\   ', '  /o~o\  ', ' /~o~o~\ ', '/o~o~o~o\', '   |_|   ')
    $out = @()
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $s = ''
        foreach ($ch in $rows[$i].ToCharArray()) {
            if ($ch -eq '★') { $s += $B + $(if ($f % 4 -lt 2) { $gold } else { $wht }) + '★' + $R }
            elseif ($ch -eq 'o') { $s += $lights[($i * 3 + $s.Length + $f) % 5] + '●' + $R }
            elseif ($ch -eq '/' -or $ch -eq '\' -or $ch -eq '~') { $s += $grn + $ch + $R }
            elseif ($ch -eq '|' -or $ch -eq '_') { $s += (C 150 100 60) + $ch + $R }
            else { $s += ' ' }
        }
        $out += $s
    }
    $out
}

function Strip($s) { $s -replace "$e\[[0-9;]*m", '' }
function Pad($s, $n) { $vis = (Strip $s).Length; $s + (' ' * [Math]::Max(0, $n - $vis)) }

[Console]::CursorVisible = $false
Clear-Host
while ($true) {
    $frame++
    Read-Log
    if ($frame % 4 -eq 1) { $cpuHist.Add((Sample-Cpu)); while ($cpuHist.Count -gt 44) { $cpuHist.RemoveAt(0) } }
    $cpuNow = if ($cpuHist.Count) { $cpuHist[$cpuHist.Count - 1] } else { 0 }
    $now = Base-Date
    $eve = Get-Date -Year $now.Year -Month 12 -Day 24 -Hour 18 -Minute 0 -Second 0
    if ($now -gt $eve) { $eve = $eve.AddYears(1) }
    $left = $eve - $now
    $procs = @(Get-Process JuleHygge).Count
    $memMb = [int]((Get-Process JuleHygge | Measure-Object WorkingSet64 -Sum).Sum / 1MB)

    $lines = @()
    $hdr = "  $B$wht NORDPOL KONTROLCENTER $R$gry ·  JuleHygge live-overvågning$R"
    $on = "$grn● ONLINE$R  "
    $gap = $W - 2 - (Strip $hdr).Length - (Strip $on).Length
    $lines += "$ice╔" + ('═' * ($W - 2)) + "╗$R"
    $lines += "$ice║$R" + $hdr + (' ' * [Math]::Max(1, $gap)) + $on + "$ice║$R"
    $lines += "$ice╚" + ('═' * ($W - 2)) + "╝$R"
    $lines += ''

    $days = '{0:00}' -f $left.Days; $hh = '{0:00}' -f $left.Hours; $mm = '{0:00}' -f $left.Minutes; $ss = '{0:00}' -f $left.Seconds
    $cd = "$B$gold$days$R$gry dage  $R$B$gold$hh$R${gry}:$R$B$gold$mm$R${gry}:$R$B$gold$ss$R"
    $top = [Math]::Max(1.0, ($cpuHist | Measure-Object -Maximum).Maximum); $sparkStr = ($cpuHist | ForEach-Object { $spark[[int][Math]::Min(8, [Math]::Max(1, [Math]::Round($_ / $top * 8)))] }) -join ''
    $cpuBar = Bar $cpuNow 10 22 $grn
    $cpuVal = '{0,5:N1} %' -f $cpuNow
    $fpsNum = 0.0; [void][double]::TryParse($fps, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$fpsNum)
    $fpsBar = Bar $fpsNum 30 22 $ice
    $g1 = '{0,4}' -f $stats.gifts; $g2 = '{0,4}' -f $stats.breaks; $g3 = '{0,3}' -f $stats.plows
    $tree = @(Tree $frame)
    $left1 = New-Object System.Collections.Generic.List[string]
    $left1.Add("$gry  JULEAFTEN OM     $R$cd")
    $left1.Add('')
    $left1.Add("$gry  CPU              $R$cpuBar $wht$cpuVal$R")
    $left1.Add("$gry  CPU-historik     $ice$sparkStr$R")
    $left1.Add("$gry  Billeder/s       $R$fpsBar $wht$fps$R")
    $left1.Add("$gry  Hukommelse       $wht$memMb MB$R")
    $left1.Add('')
    $left1.Add("$gry  GAVER BYTTET $pink$B$g1$R   $gry SNESKRED $ice$B$g2$R   $gry PLOVTURE $gold$B$g3$R")
    $rows = [Math]::Max($left1.Count, $tree.Count)
    for ($i = 0; $i -lt $rows; $i++) {
        $a = ''; if ($i -lt $left1.Count) { $a = $left1[$i] }
        $t = ''; if ($i -lt $tree.Count) { $t = $tree[$i] }
        $lines += (Pad $a 72) + $t
    }
    $lines += ''
    $lines += "$gry  ── HÆNDELSER " + ('─' * ($W - 16)) + $R
    for ($i = 0; $i -lt 9; $i++) { $lines += $(if ($i -lt $events.Count) { '  ' + $events[$i] } else { "  $D$gry·$R" }) }
    $lines += ''
    $snow = -join (1..($W - 4) | ForEach-Object { if ((Get-Random -Maximum 9) -eq 0) { '*' } elseif ((Get-Random -Maximum 7) -eq 0) { '·' } else { ' ' } })
    $lines += "  $wht$D$snow$R"

    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("$e[H")
    foreach ($l in $lines) { [void]$sb.Append($l).Append("$e[K`n") }
    [Console]::Write($sb.ToString())
    Start-Sleep -Milliseconds 250
}
