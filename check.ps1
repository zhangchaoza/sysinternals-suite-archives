git checkout main

$html = (New-Object System.Net.WebClient).DownloadString('https://live.sysinternals.com/files/')
$time = @{label = 'time'; expression = {
        if ($null -eq $global:archive_time) {
            $global:archive_time = [System.DateTimeOffset]::Parse($_.Trim().Split('     ')[0])
        }
        $global:archive_time
    }
}
$name = @{
    label      = 'name'
    expression = {
        if ($_.Trim().Split('     ')[1] -match '(?<=>)[A-Za-z0-9.\-\+]+(?=<)') {
            $Matches[0]
        }
        else {
            throw "No name matched!!!"
        }
    }
}
$url = @{
    label      = 'url'
    expression = {
        "https://live.sysinternals.com/files/$($_.name)"
    }
}
$file = @{
    label      = 'file'
    expression = {
        if ($_.name -match '(?<=\-)[A-Za-z0-9]+(?=.zip)') {
            $suffix = "-$($Matches[0])"
        }
        else {
            $suffix = ''
        }
        "temp/sysinternals-suite-$($_.time.ToString('yyyyMMddHHmmss'))$suffix.zip"
    }
}
$infos = $html.Split('<br>')
| Where-Object { $_.Contains('SysinternalsSuite') }
| Select-Object @{label = 'html'; Expression = { $_ } }, $time, $name
| Select-Object html, time, name, $url, $file

Write-Output $archive_time
Write-Output $infos

mkdir temp
foreach ($info in $infos) {
    wget -O $info.file $info.url

    if (Test-Path "$($info.name).json") {
        $meta = Get-Content "$($info.name).json" | ConvertFrom-Json
        # if ($meta.time -ne $info.time.ToUnixTimeSeconds()) {
        #     $meta.time = $info.time.ToUnixTimeSeconds()
        #     $meta.hash = (Get-FileHash $info.file).Hash
        #     $meta | ConvertTo-Json > "$($info.name).json"
        #     continue
        # }
        $hash = (Get-FileHash $info.file).Hash
        if ($meta.hash -ne $hash) {
            $meta.hash = $hash
            $meta | ConvertTo-Json > "$($info.name).json"
        }
    }
    else {
        $meta = @{
            hash = (Get-FileHash $info.file).Hash
            # time = $info.time.ToUnixTimeSeconds()
        }
        $meta | ConvertTo-Json > "$($info.name).json"
    }
}

$env:PAGER = ''
$diff = git diff --name-only
Write-Output $diff
if (-not [string]::IsNullOrEmpty($diff)) {
    # commit meta file
    $releaseTime = $archive_time
    foreach ($c in (git status -s )) {
        git add $c.Trim().Split(' ')[1]
    }
    git commit -m "Auto update at $($releaseTime.ToString('u'))"
    git push origin main

    # create tag and release
    $TAG_NAME = $releaseTime.ToString('yyyyMMddHHmmss')
    gh release create $TAG_NAME --generate-notes
    foreach ($info in $infos) {
        gh release upload $TAG_NAME $info.file
    }
}
else {
    Write-Output 'No upgrade.'
}

Write-Output "$([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())" | Set-Content lastest_check_time.txt
git add lastest_check_time.txt
git commit -m 'update lastest check time'