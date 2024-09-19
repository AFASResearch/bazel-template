param([string[]]$deps, $apphost, $exe, $dll)

foreach ($dep in $deps) {
    Import-Module $([io.path]::GetFullPath($dep))
}
[Microsoft.NET.HostModel.AppHost.HostWriter]::CreateAppHost([io.path]::GetFullPath($apphost), [io.path]::GetFullPath($exe), [io.path]::GetFullPath($dll))
