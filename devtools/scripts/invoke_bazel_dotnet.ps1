$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
gci -r src -Filter *.csproj | ? { -not [io.file]::Exists($_.Directory.FullName + "\BUILD.bazel") } | Foreach-Object -ThrottleLimit 8 -Parallel {
  [io.file]::WriteAllText($PSItem.Directory.FullName + "\BUILD", [text.regularexpressions.regex]::Replace((&"$using:scriptDir\bazel_dotnet.ps1" $PSItem.FullName) -join "`n", "(?<!\r)\n", "`r`n")) 
}
