$ver = '1.15.1'
$url = "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/$ver/onnxruntime-android-$ver.aar"
$aar = Join-Path (Get-Location) 'android/app/libs/onnxruntime-android.aar'
New-Item -ItemType Directory -Force -Path 'android/app/libs' | Out-Null
Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $aar
Write-Host ("Downloaded {0} bytes" -f (Get-Item $aar).Length)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($aar)
$abis = @('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')
foreach ($abi in $abis) {
  $entry = $zip.Entries | Where-Object { $_.FullName -eq "jni/$abi/libonnxruntime.so" } | Select-Object -First 1
  if ($null -eq $entry) {
    Write-Host "Missing $abi"
    continue
  }
  $destDir = Join-Path (Get-Location) "android/app/src/main/jniLibs/$abi"
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $dest = Join-Path $destDir 'libonnxruntime.so'
  $inStream = $entry.Open()
  $outStream = [IO.File]::Create($dest)
  $inStream.CopyTo($outStream)
  $outStream.Close()
  $inStream.Close()
  Write-Host ("Extracted {0} ({1} bytes)" -f $dest, (Get-Item $dest).Length)
}
$zip.Dispose()
Write-Host 'Done'
