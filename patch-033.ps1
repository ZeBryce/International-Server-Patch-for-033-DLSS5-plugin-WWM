# patch-for-033 · 033 燕云定制版引擎补丁（国际服适配 + 遮罩层修复）
#
#   Status  查看引擎当前状态，不改任何东西（默认）
#   Apply   打补丁
#   Revert  还原成作者发布的原版引擎（用 033 安装器卸载或升级之前先运行）
#
# 两类补丁：
#   遮罩层修复  让引擎里的"游戏主程序哈希白名单"检查直接通过。作者在引擎里写死了某一版国服主程序的哈希，
#               游戏一更新就对不上，原生遮罩随之静默失效（面板照样显示遮罩界面，画面却没有人景分离）。
#               国服、国际服都需要。
#   国际服适配  原生遮罩只认国服主程序 yysls.exe，改成认国际服的 wwm.exe。只有国际服需要；
#               脚本按游戏目录里是 wwm.exe 还是 yysls.exe 自动决定。
#   另外 V6.3.5 / V6.38 有一项"放宽库外材质检查"：遮罩库里没有的材质着色器不再让整帧遮罩作废，
#   改为当作场景处理（国际服有一部分材质不在作者的库里）。V6.3 没有这一项。可用 -NoRelax 关掉。
#
# 安全性：动手之前先把所有补丁位置在内存里还原，结果必须与作者原版引擎的 SHA-256 完全一致，
# 否则不改文件。所以 Revert 还原出来的就是原版，不需要任何备份文件。只修改游戏目录里已安装的引擎，
# 不包含、不分发作者的任何文件。
param(
    [ValidateSet('Status','Apply','Revert')]
    [string]$Action='Status',
    [string]$Engine,
    [ValidateSet('Auto','CN','Intl')]
    [string]$Client='Auto',
    [switch]$NoMaskFix,
    [switch]$NoRelax
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
      RelaxSites=@(@(0x27CCF5,@(0x39),@(0xDF)),@(0x27D543,@(0x39),@(0xDF)),@(0x27DDD3,@(0x39),@(0xDF)),@(0x27E651,@(0x3A),@(0xDF)))}
)

function Get-Sha([byte[]]$Bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Assert-GameClosed{
    if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -match '^(wwm|yysls)$'}).Count){throw '游戏正在运行，请先完全退出游戏。没有改动任何文件。'}
}
# 033 安装器在 %LOCALAPPDATA%\033Installer\index 里记着装过的游戏目录
function Find-Engine{
    $found=@()
    $index=Join-Path $env:LOCALAPPDATA '033Installer\index'
    if([IO.Directory]::Exists($index)){
        foreach($file in Get-ChildItem -LiteralPath $index -Filter '*.json' -File){
            try{$root=[string](Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json).Root}catch{continue}
            if(-not $root){continue}
            $candidate=Join-Path $root '033-runtime\033-engine.dll'
            if([IO.File]::Exists($candidate)){$found+=$candidate}
        }
    }
    $found=@($found|Sort-Object -Unique)
    if($found.Count -eq 1){return $found[0]}
    if($found.Count -gt 1){throw ('找到多个已安装的 033，请用 -Engine 指定其中一个：'+[Environment]::NewLine+($found -join [Environment]::NewLine))}
    throw '没有找到已安装的 033 引擎。请先用 033 安装器安装，或用 -Engine 指定游戏目录里的 033-runtime\033-engine.dll。'
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
function Reset-Pin([byte[]]$Bytes,$Spec){[Text.Encoding]::ASCII.GetBytes($PinOriginal).CopyTo($Bytes,$Spec.PinOffset)}
# 读引擎、按大小认版本，并证明它是作者发布的那一份：所有补丁位置还原后必须与原版 SHA-256 一致
function Read-Engine([string]$Path){
    if(-not [IO.File]::Exists($Path)){throw "找不到引擎文件：$Path"}
    $bytes=[IO.File]::ReadAllBytes($Path)
    $spec=$null;foreach($candidate in $Profiles){if($candidate.Size -eq $bytes.Length){$spec=$candidate}}
    if(-not $spec){throw ('不认识这个引擎的版本（支持 '+(($Profiles|ForEach-Object {$_.Name}) -join '、')+'），没有改动。')}
    $probe=[byte[]]$bytes.Clone()
    foreach($site in (Get-AllSites $spec)){
        if((Get-SiteState $bytes $site) -eq 'unknown'){throw ('补丁位置 0x{0:X} 的内容不认识，没有改动。' -f $site[0])}
        Set-Site $probe $site $false
    }
    if((Get-Pin $bytes $spec) -notmatch '^[0-9a-f]{64}$' -or $bytes[$spec.PinOffset+64] -ne 0){throw '主程序哈希位置的内容不认识，没有改动。'}
    Reset-Pin $probe $spec
    if((Get-Sha $probe) -ne $spec.Sha){throw ('这不是作者发布的 '+$spec.Name+' 引擎（还原补丁位置后与原版不符），没有改动。')}
    return @{Bytes=$bytes;Spec=$spec}
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
    if((Get-Pin $bytes $spec) -ne $PinOriginal){Write-Host '  （白名单里有旧版补丁写入的哈希，运行 Apply 或 Revert 会改回原样）'}
    Write-Host ('  SHA-256           ：'+(Get-Sha $bytes))
}

try{
    if(-not $Engine){$Engine=Find-Engine}
    $Engine=[IO.Path]::GetFullPath($Engine)
    switch($Action){
        'Status'{Show-Status $Engine}
        'Apply'{
            Assert-GameClosed
            $loaded=Read-Engine $Engine;$bytes=$loaded.Bytes;$spec=$loaded.Spec;$kind=Get-ClientKind $Engine
            Set-Site $bytes $spec.ExeSite (-not $NoMaskFix)
            foreach($site in $spec.IntlSites){Set-Site $bytes $site ($kind -eq 'Intl')}
            foreach($site in $spec.RelaxSites){Set-Site $bytes $site (-not $NoRelax)}
            Reset-Pin $bytes $spec
            [IO.File]::WriteAllBytes($Engine,$bytes)
            Write-Host ('已为 '+$spec.Name+' 打好补丁。') -ForegroundColor Green
            Show-Status $Engine
        }
        'Revert'{
            Assert-GameClosed
            $loaded=Read-Engine $Engine;$bytes=$loaded.Bytes;$spec=$loaded.Spec
            foreach($site in (Get-AllSites $spec)){Set-Site $bytes $site $false}
            Reset-Pin $bytes $spec
            if((Get-Sha $bytes) -ne $spec.Sha){throw '还原后与原版核对不上，没有改动。'}
            [IO.File]::WriteAllBytes($Engine,$bytes)
            Write-Host ('已还原成作者发布的 '+$spec.Name+' 原版引擎，现在可以用 033 安装器卸载或升级。') -ForegroundColor Green
        }
    }
}catch{
    Write-Host ('未完成：'+$_.Exception.Message) -ForegroundColor Red
    exit 1
}
