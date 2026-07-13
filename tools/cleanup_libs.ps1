$libs = 'android/app/libs'
$bak = 'android/app/libs_exploded_backup'
New-Item -ItemType Directory -Force -Path $bak | Out-Null
Get-ChildItem $libs | Where-Object { $_.Name -ne 'iic-2.33.11_1.aar' } | ForEach-Object {
  Move-Item -Force $_.FullName (Join-Path $bak $_.Name)
}
Write-Host 'Remaining in libs:'
Get-ChildItem $libs | ForEach-Object { $_.Name }
