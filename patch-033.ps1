# patch-for-033 · 033 燕云定制版引擎补丁（国际服适配 + 遮罩层修复）
#
#   Status  查看引擎当前状态，不改任何东西（默认）
#   Apply   打补丁
#   Revert  还原成作者发布的原版引擎（用 033 安装器卸载或升级之前先运行）
#
# 不指定 -Engine 时自动查找所有装了 033 的游戏（含同一游戏的 Win64r / Win64rh）。
# Status 逐个列出；Apply / Revert 在国服、国际服都装了时让你选择游戏，并在改动前要求输入 Y 确认。
#
# 两类补丁：
#   遮罩层修复  让引擎里的"游戏主程序哈希白名单"检查直接通过。作者在引擎里写死了某一版国服主程序的哈希，
#               游戏一更新就对不上，原生遮罩随之静默失效（面板照样显示遮罩界面，画面却没有人景分离）。
#               国服、国际服都需要。
#   国际服适配  原生遮罩只认国服主程序 yysls.exe，改成认国际服的 wwm.exe。只有国际服需要；
#               脚本按游戏目录里是 wwm.exe 还是 yysls.exe 自动决定。
#   另外 V6.3.5 / V6.38 / V6.3 威力加强版 R7 有一项"放宽库外材质检查"：遮罩库里没有的材质着色器不再让整帧遮罩作废，
#   改为当作场景处理（国际服有一部分材质不在作者的库里）。V6.3 没有这一项。可用 -NoRelax 关掉。
#
# 已知版本：还原补丁位置后的 SHA-256 必须与内置原版一致。
# 未知版本：用 PE 函数边界和多组代码/数据引用定位；首次 Apply 保存完整原始副本。
# 自动定位只能确认受支持的代码结构，不能认证来源，也不保证适配任意未来版本。
param(
    [ValidateSet('Status','Apply','Revert')]
    [string]$Action='Status',
    [string]$Engine,
    [ValidateSet('Auto','CN','Intl')]
    [string]$Client='Auto',
    [switch]$NoMaskFix,
    [switch]$NoRelax,
    [switch]$KnownOnly,
    [switch]$Yes   # 自动查找时跳过 Y 确认（-Engine 指定时本来就不询问）
)
$ErrorActionPreference='Stop'

# 引擎里两条国服主程序哈希的第一条（各版本相同）；旧版补丁曾在这里写入别的哈希，Apply/Revert 都会改回这一串
$PinOriginal='b157cc3471296bee8ed7340400f00451c76515c9b77ece02493c4d489b251c20'
$ExeCheckOld=@(0x48,0x89,0x5C,0x24,0x08)   # mov [rsp+8],rbx —— 哈希检查函数的第一条指令
$ExeCheckNew=@(0xB0,0x01,0xC3,0x90,0x90)   # mov al,1 ; ret ; nop ; nop —— 直接返回"通过"
# 每个位置：文件偏移、原版字节、补丁字节
$Profiles=@(
    @{Name='V6.3';Size=26830848;Sha='d69c4e8b1b1b8fb88d4f3c76d020d23bff697a06afabcc4e818b4326fa42b637';PinOffset=0x40FBB0
      ExeSite=@(0x2F9110,$ExeCheckOld,$ExeCheckNew)
      IntlSites=@(@(0x29BAE0,@(0x09),@(0x07)),@(0x29BAEA,@(0x22),@(0x3A)))   # 文件名长度 9→7，比对字符串 yysls.exe→wwm.exe
      RelaxSites=@()},
    @{Name='V6.3.5';Size=86242816;Sha='4dfe6ac3acd3b4dcbb47375e5a462ad0a4860b95730a2adb642a5a588d056b0c';PinOffset=0x448560
      ExeSite=@(0x327AB0,$ExeCheckOld,$ExeCheckNew)
      IntlSites=@(,@(0x2ABB74,@(0x40,0x9D),@(0xE0,0x9C)))                   # 比对字符串 yysls.exe→wwm.exe
      RelaxSites=@(@(0x2743E5,@(0x39),@(0xDF)),@(0x274BE3,@(0x39),@(0xDF)),@(0x275423,@(0x39),@(0xDF)),@(0x275C51,@(0x3A),@(0xDF)))},
    @{Name='V6.38';Size=86178304;Sha='721810f3eeee5e74c87cd5d7249be6735e61910a4eefe44a126f0e89f1a329d0';PinOffset=0x457950
      ExeSite=@(0x338F40,$ExeCheckOld,$ExeCheckNew)
      IntlSites=@(,@(0x2BA234,@(0x80),@(0x98)))
      RelaxSites=@(@(0x27CCF5,@(0x39),@(0xDF)),@(0x27D543,@(0x39),@(0xDF)),@(0x27DDD3,@(0x39),@(0xDF)),@(0x27E651,@(0x3A),@(0xDF)))},
    @{Name='V6.3 威力加强版 R7';Size=99357696;Sha='2ed0bd484068e13e289ad79554e7c0780cf784196a51c17ceed7c106af3f8470';PinOffset=0x45FD40
      ExeSite=@(0x33FA10,$ExeCheckOld,$ExeCheckNew)
      IntlSites=@(,@(0x2BB824,@(0x50),@(0x68)))
      RelaxSites=@(@(0x27CD95,@(0x39),@(0xDF)),@(0x27D5E3,@(0x39),@(0xDF)),@(0x27DE73,@(0x39),@(0xDF)),@(0x27E6F1,@(0x3A),@(0xDF)))}
)

function Get-Sha([byte[]]$Bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Assert-GameClosed{
    if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -match '^(wwm|yysls)$'}).Count){throw '游戏正在运行，请先完全退出游戏。没有改动任何文件。'}
}
$NoEngineMessage='没有找到已安装的 033 引擎。请先用 033 安装器安装，或用 -Engine 指定游戏目录里的 033-runtime\033-engine.dll。'
# 033 安装器在 %LOCALAPPDATA%\033Installer\index 里记着装过的游戏目录。同一游戏的
# Win64r / Win64rh / Win64 启动目录都可能装了 033，安装记录却只记其中一个，所以一并查找。
function Find-Engines{
    $roots=@()
    $index=Join-Path $env:LOCALAPPDATA '033Installer\index'
    if([IO.Directory]::Exists($index)){
        foreach($file in Get-ChildItem -LiteralPath $index -Filter '*.json' -File){
            try{$root=[string](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json).Root}catch{continue}
            if($root){$roots+=$root}
        }
    }
    $found=@()
    foreach($root in $roots){
        $dirs=@($root)
        $binaries=Split-Path -Parent $root
        if($binaries -and (Split-Path -Leaf $binaries) -ieq 'Binaries'){foreach($bin in 'Win64r','Win64rh','Win64'){$dirs+=(Join-Path $binaries $bin)}}
        foreach($dir in $dirs){
            $candidate=Join-Path $dir '033-runtime\033-engine.dll'
            if([IO.File]::Exists($candidate)){$found+=[IO.Path]::GetFullPath($candidate)}
        }
    }
    return @($found|Sort-Object -Unique)
}
# 一个引擎的说明：国服/国际服、033 版本、能否打补丁、所属游戏（…\Engine\Binaries）和启动目录名。
function Get-EngineInfo([string]$Path){
    $kind=try{Get-ClientKind $Path}catch{''}
    $client=$(switch($kind){'Intl'{'国际服'}'CN'{'国服'}default{'未知客户端'}})
    try{$version=(Read-Engine $Path).Spec.Name;$supported=$true}catch{$version='未识别的版本';$supported=$false}
    $folder=Split-Path -Parent (Split-Path -Parent $Path)
    return [pscustomobject]@{Path=$Path;Client=$client;Version=$version;Supported=$supported;Game=(Split-Path -Parent $folder);Folder=(Split-Path -Leaf $folder)}
}
# 自动查找时选出要处理的引擎：只有一个游戏就用它，否则列出编号让用户选；改动前要求输入 Y。
function Select-Targets([string]$Verb){
    $all=@(Find-Engines|ForEach-Object {Get-EngineInfo $_})
    if(-not $all.Count){throw $NoEngineMessage}
    foreach($e in @($all|Where-Object {-not $_.Supported})){
        Write-Host ('跳过：'+$e.Client+' '+$e.Folder+' 的 033 是'+$e.Version+'，不需要或无法打补丁（例如 V6.0）。') -ForegroundColor DarkYellow
    }
    $usable=@($all|Where-Object {$_.Supported})
    if(-not $usable.Count){throw '找到的 033 引擎都不需要或无法打补丁，没有改动任何文件。'}
    $games=@($usable|Group-Object -Property Game)
    $chosen=$games[0]
    if($games.Count -gt 1){
        Write-Host ''
        Write-Host ('找到多个装了 033 的游戏，请选择要'+$Verb+'的一个：')
        for($i=0;$i -lt $games.Count;$i++){
            $group=@($games[$i].Group)
            Write-Host ('  ['+($i+1)+'] '+$group[0].Client+'  033 '+(@($group|ForEach-Object {$_.Version}|Sort-Object -Unique) -join ' / ')+'  启动目录：'+(@($group|ForEach-Object {$_.Folder}) -join '、'))
            Write-Host ('      '+$games[$i].Name)
        }
        $answer=Read-Host ('输入编号 1-'+$games.Count+' 后回车（直接回车取消）')
        $number=0
        if(-not [int]::TryParse(([string]$answer).Trim(),[ref]$number) -or $number -lt 1 -or $number -gt $games.Count){throw '已取消，没有改动任何文件。'}
        $chosen=$games[$number-1]
    }
    $targets=@($chosen.Group)
    Write-Host ''
    Write-Host ('将要'+$Verb+'以下 '+$targets.Count+' 个 033 引擎：')
    foreach($t in $targets){Write-Host ('  '+$t.Client+'  033 '+$t.Version+'  '+$t.Path)}
    if(-not $Yes){
        $confirm=Read-Host '确认继续请输入 Y 后回车，输入其他内容取消'
        if(([string]$confirm).Trim() -notmatch '^[Yy]$'){throw '已取消，没有改动任何文件。'}
    }
    return @($targets|ForEach-Object {$_.Path})
}
function Get-SiteState([byte[]]$Bytes,$Site){
    $at=[int]$Site[0];$isOld=$true;$isNew=$true
    for($i=0;$i -lt $Site[1].Count;$i++){
        if($Bytes[$at+$i] -ne $Site[1][$i]){$isOld=$false}
        if($Bytes[$at+$i] -ne $Site[2][$i]){$isNew=$false}
    }
    if($isOld){return 'original'};if($isNew){return 'patched'};return 'unknown'
}
function Set-Site([byte[]]$Bytes,$Site,[bool]$Patched){
    $values=$(if($Patched){$Site[2]}else{$Site[1]})
    for($i=0;$i -lt $values.Count;$i++){$Bytes[[int]$Site[0]+$i]=[byte]$values[$i]}
}
function Get-AllSites($Spec){return @(,$Spec.ExeSite)+@($Spec.IntlSites)+@($Spec.RelaxSites)}
function Get-Pin([byte[]]$Bytes,$Spec){return [Text.Encoding]::ASCII.GetString($Bytes,$Spec.PinOffset,64)}
function Get-OriginalPin($Spec){if($Spec.ContainsKey('OriginalPin')){return $Spec.OriginalPin};return $PinOriginal}
function Reset-Pin([byte[]]$Bytes,$Spec){[Text.Encoding]::ASCII.GetBytes((Get-OriginalPin $Spec)).CopyTo($Bytes,$Spec.PinOffset)}
function Get-AutoSpec([byte[]]$Bytes){
    if(-not ('EngineDetector' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'auto-detect.cs')}
    $d=[EngineDetector]::Locate($Bytes)
    $sha=Get-Sha $Bytes
    $relax=@();for($i=0;$i -lt $d.RelaxOffsets.Length;$i++){$relax+=,@($d.RelaxOffsets[$i],@($d.RelaxOld[$i]),@(0xDF))}
    return @{Name=('自动适配 '+$sha.Substring(0,12));Size=$Bytes.Length;Sha=$sha;Auto=$true
        OriginalPin=[Text.Encoding]::ASCII.GetString($Bytes,$d.PinOffset,64);PinOffset=$d.PinOffset
        ExeSite=@($d.ExeOffset,$ExeCheckOld,$ExeCheckNew)
        IntlSites=@(,@($d.IntlOffset,$d.IntlOld,$d.IntlNew));RelaxSites=$relax}
}
function Test-Profile([byte[]]$Bytes,$Spec){
    if($Bytes.Length -ne $Spec.Size){return $false}
    $probe=[byte[]]$Bytes.Clone()
    foreach($site in (Get-AllSites $Spec)){
        if((Get-SiteState $Bytes $site) -eq 'unknown'){return $false}
        Set-Site $probe $site $false
    }
    if((Get-Pin $Bytes $Spec) -cnotmatch '^[0-9a-f]{64}$' -or $Bytes[$Spec.PinOffset+64] -ne 0){return $false}
    # Auto profiles never rewrite a whitelist string; only legacy built-in profiles do.
    if($Spec.Auto -and (Get-Pin $Bytes $Spec) -cne $Spec.OriginalPin){return $false}
    Reset-Pin $probe $Spec
    return (Get-Sha $probe) -eq $Spec.Sha
}
# No offsets are trusted from disk. A saved original is hashed and scanned again.
function Read-SavedProfile([string]$Path,[byte[]]$Bytes){
    $stateDir=$Path+'.patch-033'
    if(-not [IO.Directory]::Exists($stateDir)){return $null}
    foreach($file in Get-ChildItem -LiteralPath $stateDir -Filter '*.original.dll' -File){
        if($file.Name -notmatch '^([0-9a-f]{64})\.original\.dll$' -or $file.Length -ne $Bytes.Length){continue}
        $expected=$Matches[1]
        $original=[IO.File]::ReadAllBytes($file.FullName)
        if((Get-Sha $original) -ne $expected){throw ('恢复副本校验失败：'+$file.FullName)}
        $spec=Get-AutoSpec $original
        if(Test-Profile $Bytes $spec){return $spec}
    }
    return $null
}
# Try all built-in profiles of this size, then local recovery data, then structural detection.
function Read-Engine([string]$Path){
    if(-not [IO.File]::Exists($Path)){throw "找不到引擎文件：$Path"}
    $bytes=[IO.File]::ReadAllBytes($Path)
    foreach($candidate in $Profiles){
        if($candidate.Size -eq $bytes.Length -and (Test-Profile $bytes $candidate)){return @{Bytes=$bytes;Spec=$candidate}}
    }
    if($KnownOnly){throw '文件与内置已知版本不符；-KnownOnly 禁止自动适配。没有改动。'}
    $spec=Read-SavedProfile $Path $bytes
    if(-not $spec){$spec=Get-AutoSpec $bytes}
    return @{Bytes=$bytes;Spec=$spec}
}
function Save-Original([string]$Path,[byte[]]$Bytes,$Spec){
    if(-not $Spec.Auto){return}
    $original=[byte[]]$Bytes.Clone()
    foreach($site in (Get-AllSites $Spec)){Set-Site $original $site $false}
    if((Get-Sha $original) -ne $Spec.Sha){throw '恢复副本与原始哈希不符，没有改动。'}
    $stateDir=$Path+'.patch-033'
    [void][IO.Directory]::CreateDirectory($stateDir)
    $backup=Join-Path $stateDir ($Spec.Sha+'.original.dll')
    if([IO.File]::Exists($backup)){
        if((Get-Sha ([IO.File]::ReadAllBytes($backup))) -ne $Spec.Sha){throw '已有恢复副本损坏，没有改动。'}
        return
    }
    $temp=Join-Path $stateDir ([Guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllBytes($temp,$original)
        if((Get-Sha ([IO.File]::ReadAllBytes($temp))) -ne $Spec.Sha){throw '恢复副本写入校验失败，没有改动。'}
        [IO.File]::Move($temp,$backup)
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
    Write-Host ('已保存原始引擎：'+$backup)
}
function Write-Engine([string]$Path,[byte[]]$Bytes,[string]$ExpectedSha){
    $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if((Get-Sha ([IO.File]::ReadAllBytes($temp))) -ne (Get-Sha $Bytes)){throw '临时文件写入校验失败，没有改动引擎。'}
        Assert-GameClosed
        if((Get-Sha ([IO.File]::ReadAllBytes($Path))) -ne $ExpectedSha){throw '引擎在处理期间被其他程序修改，请重试。没有覆盖文件。'}
        [IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function Get-ClientKind([string]$EnginePath){
    if($Client -ne 'Auto'){return $Client}
    $dir=Split-Path -Parent (Split-Path -Parent $EnginePath)
    if([IO.File]::Exists((Join-Path $dir 'wwm.exe'))){return 'Intl'}
    if([IO.File]::Exists((Join-Path $dir 'yysls.exe'))){return 'CN'}
    throw '引擎旁边既没有 wwm.exe 也没有 yysls.exe，无法判断国服还是国际服，请用 -Client CN 或 -Client Intl 指定。'
}
function Format-State([byte[]]$Bytes,$Sites){
    if(-not @($Sites).Count){return '（此版本没有这一项）'}
    $states=@($Sites|ForEach-Object {Get-SiteState $Bytes $_}|Sort-Object -Unique)
    return ($states -join ' / ')
}
function Show-Status([string]$Path){
    $loaded=Read-Engine $Path;$bytes=$loaded.Bytes;$spec=$loaded.Spec
    Write-Host ('引擎：'+$Path)
    Write-Host ('  版本              ：'+$spec.Name+'（'+$(if((Get-ClientKind $Path) -eq 'Intl'){'国际服'}else{'国服'})+'）')
    Write-Host ('  遮罩层修复        ：'+(Format-State $bytes @(,$spec.ExeSite)))
    Write-Host ('  国际服适配        ：'+(Format-State $bytes $spec.IntlSites))
    Write-Host ('  放宽库外材质检查  ：'+(Format-State $bytes $spec.RelaxSites))
    if($spec.Auto){
        Write-Host '  识别方式          ：代码特征自动定位（来源未经内置哈希认证）'
        Write-Host ('  原始 SHA-256      ：'+$spec.Sha)
        Write-Host ('  恢复副本目录      ：'+$Path+'.patch-033')
    }
    if((Get-Pin $bytes $spec) -cne (Get-OriginalPin $spec)){Write-Host '  （白名单里有旧版补丁写入的哈希，运行 Apply 或 Revert 会改回原样）'}
    Write-Host ('  SHA-256           ：'+(Get-Sha $bytes))
}

function Invoke-Apply([string]$Path){
    $loaded=Read-Engine $Path;$bytes=$loaded.Bytes;$spec=$loaded.Spec;$kind=Get-ClientKind $Path
    $before=Get-Sha $bytes
    Save-Original $Path $bytes $spec
    Set-Site $bytes $spec.ExeSite (-not $NoMaskFix)
    foreach($site in $spec.IntlSites){Set-Site $bytes $site ($kind -eq 'Intl')}
    foreach($site in $spec.RelaxSites){Set-Site $bytes $site (-not $NoRelax)}
    Reset-Pin $bytes $spec
    Write-Engine $Path $bytes $before
    Write-Host ('已为 '+$spec.Name+' 打好补丁。') -ForegroundColor Green
    Show-Status $Path
}
function Invoke-Revert([string]$Path){
    $loaded=Read-Engine $Path;$bytes=$loaded.Bytes;$spec=$loaded.Spec
    $before=Get-Sha $bytes
    foreach($site in (Get-AllSites $spec)){Set-Site $bytes $site $false}
    Reset-Pin $bytes $spec
    if((Get-Sha $bytes) -ne $spec.Sha){throw '还原后与原版核对不上，没有改动。'}
    Write-Engine $Path $bytes $before
    Write-Host ('已还原 '+$spec.Name+' 补丁前的引擎：'+$Path) -ForegroundColor Green
}

try{
    if($Engine){$Engine=[IO.Path]::GetFullPath($Engine)}
    switch($Action){
        'Status'{
            $paths=$(if($Engine){@($Engine)}else{@(Find-Engines)})
            if(-not $paths.Count){throw $NoEngineMessage}
            for($i=0;$i -lt $paths.Count;$i++){
                if($i){Write-Host ''}
                try{Show-Status $paths[$i]}catch{
                    Write-Host ('引擎：'+$paths[$i])
                    Write-Host '  未识别的 033 版本（例如 V6.0），不需要或无法打补丁。' -ForegroundColor DarkYellow
                }
            }
        }
        'Apply'{
            Assert-GameClosed
            $targets=$(if($Engine){@($Engine)}else{@(Select-Targets '打补丁')})
            foreach($t in $targets){Write-Host '';Invoke-Apply $t}
        }
        'Revert'{
            Assert-GameClosed
            $targets=$(if($Engine){@($Engine)}else{@(Select-Targets '还原')})
            foreach($t in $targets){Write-Host '';Invoke-Revert $t}
            Write-Host '现在可以用 033 安装器卸载或升级。' -ForegroundColor Green
        }
    }
}catch{
    Write-Host ('未完成：'+$_.Exception.Message) -ForegroundColor Red
    exit 1
}
