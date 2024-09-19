param($path)

$root = $pwd
$dir = [io.path]::GetDirectoryName($path)
[xml]$xml = gc $path
$Label = [io.path]::GetFileNameWithoutExtension($path)
$Visibility = switch -Wildcard ([io.path]::GetRelativePath($root, $path) -replace ('\\','/')) {
    "generator/modules/businessactivityapi/*" { '"//generator/integration:__subpackages__", "//generator/modules/businessactivityapi:__subpackages__", "//generator/modules/businessactivities:__subpackages__", "//generator/modules/activities:__subpackages__"'; Break }
    "generator/modules/businessactivities*" { '"//generator/integration:__subpackages__", "//generator/modules/businessactivities:__subpackages__", "//generator/modules/businessactivitiesmeta:__subpackages__", "//generator/modules/activities:__subpackages__"'; Break }
    "generator/modules/*" { '"//generator/integration:__subpackages__", "//generator/modules/' + ([io.path]::GetRelativePath($root, $path) -split '[\\/]')[2] + ':__subpackages__"'; Break }
    "generator/*" { '"//generator:__subpackages__"'; Break }
    "host/src/Afas.Cqrs.Interop.Server/*" { '"//host:__subpackages__", "//generator/libraries/testing/src/Afas.Generator.Testing:__pkg__"'; Break }
    "host/src/*" { '"//host:__subpackages__"'; Break }
    "host/tests/*" { '"//host/tests/' + ([io.path]::GetRelativePath($root, $path) -split '[\\/]')[2] + ':__subpackages__"'; Break }
    "shared/tests/*" { '"//shared/tests/' + ([io.path]::GetRelativePath($root, $path) -split '[\\/]')[2] + ':__subpackages__"'; Break }
    default { '"//visibility:public"'; Break }
}
$type = if ($path.EndsWith("Test.csproj") -or $path.EndsWith("Tests.csproj")) {
    "core_nunit3_test"
} elseif ($xml | Select-Xml -XPath '/Project/PropertyGroup/OutputType[text()="Exe"]') { 
    "core_binary"
} else { 
    "core_library" 
}
$resxs = $xml | Select-Xml -XPath '/Project/ItemGroup/EmbeddedResource[child::Generator="ResXFileCodeGenerator" or child::Generator="PublicResXFileCodeGenerator" or @Generator="ResXFileCodeGenerator"]'
$resources = ($xml | Select-Xml -XPath '/Project/ItemGroup/EmbeddedResource[@Include]' | % {
    "`"$($_.Node.Include -replace ('\\','/'))`""
}) -join ', '
$remove_resources = ($xml | Select-Xml -XPath '/Project/ItemGroup/EmbeddedResource[@Remove]' | % {
    "`"$($_.Node.Remove -replace ('\\','/'))`", "
}) -join ''
$remove_compile = ($xml | Select-Xml -XPath '/Project/ItemGroup/Compile[@Remove]' | % {
    ", `"$($_.Node.Remove -replace ('\\','/'))`""
}) -join ''

$list = @()
if ($type -ne 'core_nunit3_test') {
    $list += "`"$type`""
}
if ($resources) {
    $list += '"core_resource_multi"'
}
if ($resxs) {
    $list += '"core_resx"'
}

if ($list) {
"load(`"@io_bazel_rules_dotnet//dotnet:defs.bzl`", $($list -join ', '))"
}
if ($type -eq 'core_nunit3_test') {
'load("//devtools/bazel:test.bzl", "core_nunit3_test")'
}
'resources = []'

[string]$bazelSrc = $xml | Select-Xml -XPath "//BazelSrcs"
if ($bazelSrc) {
    $bazelSrc
}

if ($resources)
{
@"

core_resource_multi(name = "Resources", identifierBase = "Afas", srcs = glob([$resources], exclude = [$remove_resources"**/obj/**", "**/bin/**"]))
resources.append("Resources")
"@
}

foreach ($resx in $resxs) {
    $update = $resx.Node.Update -replace ('\\','/')
    $name = $update -replace ('/', '.')
    $out = [io.path]::GetFileNameWithoutExtension($name)
    if ($name -eq $update) {
        $name = '_' + $name
    }
@"
core_resx(
    name = "$name",
    src = "$update",
    out = "Afas.$out.resources",
)
resources.append("$name")
"@
}

''
''

$data = $xml | Select-Xml -XPath '/Project/ItemGroup/*[child::CopyToOutputDirectory]' | % {
    "`"$(($_.Node.Include ?? $_.Node.Update) -replace ('\\','/'))`""
}

$data2 = $xml | Select-Xml -XPath '/Project/*/BazelData' | % {
    "`"$($_.Node.InnerText -replace ('\\','/'))`""
}

$data = if ($data) { "glob([$(($data + $data2) -join ', ')], exclude = [`"**/obj/**`", `"**/bin/**`"])" } else { "[$($data2 -join ', ')]" }
@"
filegroup(
  name = "${Label}__data",
  srcs = $data,
  visibility = [$Visibility]
)
"@

$filegroups = $xml | Select-Xml -Xpath '/Project/ItemGroup/FileGroup[@Include]'
if ($filegroups) {
    foreach ($filegroup in $filegroups) {
        $name = $filegroup.Node.Name
        $include = $filegroup.Node.Include
        $glob = if ($include.Contains('*')) { "glob([`"$include`"], exclude = [`"**/obj/**`", `"**/bin/**`"])" } else { "[`"$include`"]" }
    
@"
filegroup(
  name = "$name",
  srcs = $glob,
  visibility = ["//visibility:public"],
)
"@
    }
}

$additionalFilesGroups = $xml | Select-Xml -XPath "/Project/ItemGroup/AdditionalFiles[starts-with(@Include, '**')]"
foreach ($additionalFilesGroup in $additionalFilesGroups) {
    $include = $additionalFilesGroup.Node.Include -replace ('\\','/')
@"
filegroup(
  name = "$(($include.Substring(3) -split '/')[0])",
  srcs = glob(["$include"], exclude = ["**/obj/**", "**/bin/**"]),
  visibility = [$Visibility],
)
"@
}

if (-not $filegroups -and -not $additionalFilesGroups) {
    ''
}

@"
$type(
  name = "$Label",
  out = "$Label.dll",
"@

[string]$sdk = $xml | Select-Xml -XPath '/*/@Sdk'
if ($sdk -eq 'Microsoft.NET.Sdk.Web') {
@'
  runtime_properties = {
    "System.GC.Server": "true"
  },
'@
}

if ($xml | Select-Xml -XPath "//BazelTestOnly[text()='true']" ) {
    @'
  testonly = True,
'@
}

if ($xml | Select-Xml -XPath "//Nullable[text()='enable']" ) {
    @'
  nullable = True,
'@
}

if ($xml | Select-Xml -XPath "/Project/PropertyGroup/AllowUnsafeBlocks[text()='true']" ) {
    @'
  unsafe = True,
'@
}

$af = &{
    $additionalFiles = @()
    $additionalFiles += $xml | Select-Xml -XPath "/Project/ItemGroup/AdditionalFiles[starts-with(@Include, '**')]" | % { 
        $include = $_.Node.Include -replace ('\\','/')
        "`n    `"$(($include.Substring(3) -split '/')[0])`""
    }

    $additionalFiles += $xml | Select-Xml -XPath "/Project/ItemGroup/AdditionalFiles[starts-with(@Include, '..')]" | % { 
        $include = $_.Node.Include -replace ('\\','/')
        $split = $include.Substring(3) -split '/'
        $rel = [io.path]::GetRelativePath($root, [io.path]::Combine($dir, "..", $split[0]))
        $target = "//$($rel -replace '\\', '/'):$($split[2])"
        "`n    `"$target`""
    }
    if ($additionalFiles) {
        "[$($additionalFiles -join ',')`n  ]"
    }
    $additionalFilesGlobs = $xml | Select-Xml -XPath "/Project/ItemGroup/AdditionalFiles[not(starts-with(@Include, '**') or starts-with(@Include, '..'))]" | % {
        $include = $_.Node.Include -replace ('\\','/')
        "`"$include`""
    }
    if ($additionalFilesGlobs) {
        "glob([$($additionalFilesGlobs -join ', ')], exclude = [`"**/obj/**`", `"**/bin/**`"])"
    }
} -join ' + '

if ($af) {
@"
  additional_files = $($af -join ' + '),
"@
}

$winsdk = $xml | Select-Xml -XPath "//UseWindowsForms[text()='true'] | //UseWPF[text()='true']"
if ($winsdk) {
@'
  xamls = glob(["**/*.xaml"], exclude = ["**/obj/**", "**/bin/**"]),
'@
}

$srcs = if ($bazelSrc) { 'srcs' } else { &{
    "glob([`"**/*.cs`"], exclude = [`"**/obj/**`", `"**/bin/**`"$remove_compile])"
    $imports = ($xml | Select-Xml -XPath '/Project/Import[@Project]' | % {
        $rel = [io.path]::GetRelativePath($root, [io.path]::Combine($dir, $_.Node.Project.ToString()))
        $target = "//$([io.path]::GetDirectoryName($rel) -replace '\\', '/')" # :$([io.path]::GetFileNameWithoutExtension($rel))
        "`"$target`""
    }) -join ', '
    if ($imports) {
        "[$imports]"
    }
} }

@"
  srcs = $($srcs -join ' + '),
  resources = resources,
  data = [":${Label}__data"],
  deps = [
"@

# TODO netstandard
$deps = @('"@nuget//microsoft.netcore.app.ref"')
if ($xml | Select-Xml -XPath '/Project/PropertyGroup/TargetFramework[contains(text(), "-windows10")]') {
    $deps += '"@nuget//microsoft.windows.sdk.net.ref"'
}
if ($winsdk) {
    $deps += '"@nuget//microsoft.windowsdesktop.app.ref"'
}

$deps += &{
    $xml | Select-Xml -XPath '//PackageReference'
    $xml | Select-Xml -XPath '//FrameworkReference'
    $xml | Select-Xml -XPath '//ProjectReference'
} | % {
    if ($_.Node.Name -eq 'FrameworkReference') {
        "`"@nuget//$($_.Node.Include.ToString().ToLower()).ref`""
    } elseif ($_.Node.Name -eq 'PackageReference') {
        if ($_.Node.Include -eq 'Microsoft.NET.Test.Sdk') {
            "`"@nuget//microsoft.testplatform.testhost`""
            "`"@nuget//microsoft.codecoverage`""
        } else {
            "`"@nuget//$($_.Node.Include.ToString().ToLower())`""
        }
    } else {
        $rel = [io.path]::GetRelativePath($root, [io.path]::Combine($dir, $_.Node.Include.ToString()))
        $target = "//$([io.path]::GetDirectoryName($rel) -replace '\\', '/'):$([io.path]::GetFileNameWithoutExtension($rel))"
        "`"$target`""
    }
    # TODO -Unique can be dropped. Should be fixed in csprojs
 } | Select-Object -Unique
if ($deps) {
    '    ' + ($deps -join ",`n    ")
}
@"
  ],
  dotnet_context_data = "//:afas_context_data",
  visibility = [$Visibility]
)
"@