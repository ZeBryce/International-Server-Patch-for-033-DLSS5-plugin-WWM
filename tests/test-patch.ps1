param(
    [Parameter(Mandatory=$true)][string]$SampleEngine,
    [string]$PowerShellExe='powershell.exe'
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$script=Join-Path $repo 'patch-033.ps1'
$testRoot=Join-Path $repo ('patch-033-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$engine=Join-Path $testRoot '033-engine.dll'
$checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('PASS '+$Message)}
function Hash([byte[]]$Bytes){$s=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($s.ComputeHash($Bytes))}finally{$s.Dispose()}}
function Run([string[]]$Options,[bool]$Success=$true){
    $clientOptions=@();if($Options -notcontains '-Client'){$clientOptions=@('-Client','Intl')}
    $out=& $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script -Engine $engine @clientOptions @Options 2>&1
    $code=$LASTEXITCODE
    if(($code -eq 0) -ne $Success){throw ('Unexpected exit '+$code+': '+($out -join "`n"))}
    return ($out -join "`n")
}
function Write-Sample([byte[]]$Bytes){[IO.File]::WriteAllBytes($engine,$Bytes)}
try{
    Copy-Item -LiteralPath $SampleEngine -Destination $engine
    $null=Run @('-Action','Revert','-KnownOnly')
    $original=[IO.File]::ReadAllBytes($engine)
    Add-Type -Path (Join-Path $repo 'auto-detect.cs')
    $d=[EngineDetector]::Locate($original)
    Check ($d.ExeOffset -ge 0 -and $d.RelaxOffsets.Length -eq 4) 'original sample is structurally recognized'
    $null=Run @('-Action','Apply','-KnownOnly')
    $knownPatched=[IO.File]::ReadAllBytes($engine)
    $null=Run @('-Action','Apply','-KnownOnly')
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $knownPatched)) 'known Apply is idempotent'
    $null=Run @('-Action','Revert','-KnownOnly')
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $original)) 'known Revert restores exact original'

    # Move every section's raw data by one alignment unit. RVAs and executable
    # semantics stay unchanged, while every old fixed file offset becomes wrong.
    $pe=[BitConverter]::ToInt32($original,60)
    $sectionTable=$pe+24+[BitConverter]::ToUInt16($original,$pe+20)
    $count=[BitConverter]::ToUInt16($original,$pe+6)
    $shift=[BitConverter]::ToInt32($original,$pe+24+36)
    $first=[int]::MaxValue
    for($i=0;$i -lt $count;$i++){
        $p=$sectionTable+$i*40
        if([BitConverter]::ToUInt32($original,$p+16) -gt 0){$first=[Math]::Min($first,[BitConverter]::ToInt32($original,$p+20))}
    }
    $future=New-Object byte[] ($original.Length+$shift)
    [Array]::Copy($original,0,$future,0,$first)
    [Array]::Copy($original,$first,$future,$first+$shift,$original.Length-$first)
    for($i=0;$i -lt $count;$i++){
        $p=$sectionTable+$i*40
        if([BitConverter]::ToUInt32($future,$p+16) -gt 0){[BitConverter]::GetBytes([BitConverter]::ToInt32($future,$p+20)+$shift).CopyTo($future,$p+20)}
    }
    $moved=[EngineDetector]::Locate($future)
    Check ($moved.ExeOffset -eq $d.ExeOffset+$shift -and $moved.IntlOffset -eq $d.IntlOffset+$shift -and $moved.PinOffset -eq $d.PinOffset+$shift) 'scanner follows relocated raw sections'
    Write-Sample $future
    $null=Run @('-Action','Status','-KnownOnly') $false
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $future)) 'KnownOnly rejects unknown engine without writing'
    $null=Run @('-Action','Status')
    Check (-not (Test-Path -LiteralPath ($engine+'.patch-033'))) 'Status does not create recovery data'
    $null=Run @('-Action','Apply')
    $autoPatched=[IO.File]::ReadAllBytes($engine)
    $expected=[byte[]]$future.Clone()
    [byte[]]@(0xB0,0x01,0xC3,0x90,0x90) | ForEach-Object -Begin {$j=$moved.ExeOffset} -Process {$expected[$j++]=$_}
    $moved.IntlNew.CopyTo($expected,$moved.IntlOffset)
    foreach($p in $moved.RelaxOffsets){$expected[$p]=0xDF}
    Check ((Hash $autoPatched) -eq (Hash $expected)) 'auto Apply changes only intended bytes'
    $backups=@(Get-ChildItem -LiteralPath ($engine+'.patch-033') -Filter '*.original.dll')
    Check ($backups.Count -eq 1 -and (Hash ([IO.File]::ReadAllBytes($backups[0].FullName))) -eq (Hash $future)) 'auto Apply saves exact original before patching'
    $null=Run @('-Action','Apply')
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $autoPatched)) 'auto Apply is idempotent'
    $null=Run @('-Action','Status')
    $null=Run @('-Action','Apply','-NoMaskFix','-NoRelax')
    $optionsExpected=[byte[]]$future.Clone();$moved.IntlNew.CopyTo($optionsExpected,$moved.IntlOffset)
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $optionsExpected)) 'NoMaskFix and NoRelax are respected'
    $null=Run @('-Action','Apply','-Client','CN')
    $cnExpected=[byte[]]$expected.Clone();$moved.IntlOld.CopyTo($cnExpected,$moved.IntlOffset)
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $cnExpected)) 'CN restores original game-name reference'
    $null=Run @('-Action','Revert')
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $future)) 'auto Revert restores exact pre-patch SHA'

    # Detect unexpected modifications in a patched file using its saved original.
    Write-Sample $autoPatched
    $tampered=[byte[]]$autoPatched.Clone();$tampered[$tampered.Length-1]=$tampered[$tampered.Length-1] -bxor 1
    Write-Sample $tampered
    $null=Run @('-Action','Revert') $false
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $tampered)) 'unrelated modification of patched DLL is rejected'
    Write-Sample $autoPatched
    $backupPath=$backups[0].FullName
    $broken=[byte[]]$future.Clone();$broken[0]=0
    [IO.File]::WriteAllBytes($backupPath,$broken)
    $null=Run @('-Action','Revert') $false
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $autoPatched)) 'corrupt recovery data is rejected without touching DLL'
    [IO.File]::WriteAllBytes($backupPath,$future)
    $hidden=$backupPath+'.hidden';[IO.File]::Move($backupPath,$hidden)
    $null=Run @('-Action','Revert') $false
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $autoPatched)) 'missing recovery data is rejected'
    [IO.File]::Move($hidden,$backupPath)

    $missing=[byte[]]$future.Clone();$missing[$moved.RelaxOffsets[0]+1]=0x90
    Write-Sample $missing
    $null=Run @('-Action','Apply') $false
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $missing)) 'incomplete material-check family is rejected'
    $ambiguous=[byte[]]$future.Clone()
    # Copy a complete material signature into the executable section's padding.
    [Array]::Copy($future,$moved.RelaxOffsets[0]-32,$ambiguous,$first+$shift,128)
    Write-Sample $ambiguous
    $null=Run @('-Action','Apply') $false
    Check ((Hash ([IO.File]::ReadAllBytes($engine))) -eq (Hash $ambiguous)) 'duplicate material signature is rejected'
    Write-Sample ([byte[]]@(0x4d,0x5a,0,0))
    $null=Run @('-Action','Apply') $false
    Check ((Get-Item -LiteralPath $engine).Length -eq 4) 'truncated PE is rejected'
    Write-Host ("All $checks checks passed.")
}finally{
    # Delete only the freshly created, verified test directory under the repository root.
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath($repo).TrimEnd('\')+'\'
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^patch-033-test-[0-9a-f]{32}$'){
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
