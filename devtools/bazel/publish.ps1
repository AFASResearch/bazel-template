param ($hostmodel, $apphost, $dir, [String[]] $entrypoints, $runfiles)

Add-Type -LiteralPath $hostmodel

function link($runfile, $name) {
    $fullname = [io.path]::Combine($dir, $name)
    [io.directory]::CreateDirectory([io.path]::GetDirectoryName($fullname)) | out-null

    cp $runfile $fullname
    # symlink results in an error when using powershell.exe, not for pwsh.exe:
    # new-item : Administrator privilege required for this operation.
    # new-item -Name $fullname -ItemType SymbolicLink -Value $([io.path]::Combine($pwd, $runfile)) | out-null
}

$targets = @{}
$libraries = @{}

foreach($line in gc $runfiles)
{
    if ($line.StartsWith('{')) {
        $data = ConvertFrom-Json $line
        $files = $data.files
        $key = $data.name + "/" + $data.version

        $targets[$key] = @{}

        if ($data.dependencies) {
            $targets[$key]["dependencies"] = $data.dependencies
        }

        foreach($file in $files) {
            if (-not $file.EndsWith(".dll")) {
                continue
            }

            $r = $file.IndexOf("/runtimes/")
            if ($r -ne -1) {

                $rid_start = $r + "/runtimes/".Length
                $rid_end = $file.IndexOf('/', $rid_start)

                if (-not $targets[$key]["runtimeTargets"]) {
                    $targets[$key]["runtimeTargets"] = @{}
                }

                $targets[$key]["runtimeTargets"][$file.SubString($r + 1)] = @{
                    rid = $file.SubString($rid_start, $rid_end - $rid_start)
                    assetType = if ($file.IndexOf("/native/") -ne -1) { "native" } else { "runtime" }
                }
            } else {
                if (-not $targets[$key]["runtime"]) {
                    $targets[$key]["runtime"] = @{}
                }

                $targets[$key]["runtime"][$([io.path]::GetFileName($file))] = @{}
            }
        }

        $libraries[$key] = @{
            type = $data.type
            serviceable = $false
            sha512 = ""
        }
    } else {
        $files = @($line)
    }

    foreach($runfile in $files) {
        if ($runfile.EndsWith(".resources.dll")) {
            # combine filename and parent folder name
            link $runfile $([io.path]::Combine([io.path]::GetFileName([io.path]::GetDirectoryName($runfile)), [io.path]::GetFileName($runfile)))
        } elseif ($runfile.IndexOf("/runtimes/") -ne -1) {
            if ($runfile.IndexOf("/runtimes/win/") -ne -1) {
                # for some reason the /runtimes/win/ binaries are also published in the root
                # link $runfile $([io.path]::GetFileName($runfile))
            }
    
            link $runfile $runfile.Substring($runfile.IndexOf("/runtimes/") + 1)
        } elseif ($runfile.EndsWith(".dll") -or $runfile.EndsWith(".pdb")) {
            # link in root
            link $runfile $([io.path]::GetFileName($runfile))
        } elseif ($runfile.IndexOf("/src/") -ne -1) {
            # use relative structure for data files to project root src/*
            link $runfile $runfile.SubString($runfile.IndexOf('/', $runfile.IndexOf("/src/") + "/src/".Length) + 1)
        } else {
            link $runfile $([io.path]::GetFileName($runfile))
        }
    }
}

foreach($entrypoint in $entrypoints.Split(','))
{
    $filename = [io.path]::GetFileNameWithoutExtension($entrypoint)
    $exe = [io.path]::Combine($dir, $filename + ".exe")
    [Microsoft.NET.HostModel.AppHost.HostWriter]::CreateAppHost($apphost, $exe, [io.path]::GetFileName($entrypoint))

    echo @"
{
    "runtimeOptions": {
        "tfm": "net8.0",
        "frameworks": [
          {
            "name": "Microsoft.NETCore.App",
            "version": "8.0.0"
          },
          {
            "name": "Microsoft.AspNetCore.App",
            "version": "8.0.0"
          }
        ],
        "configProperties": {
          "System.GC.Server": true,
          "System.Reflection.Metadata.MetadataUpdater.IsSupported": false,
          "System.Runtime.Serialization.EnableUnsafeBinaryFormatterSerialization": false
        }
    }
}
"@ > $([io.path]::Combine($dir, $filename + ".runtimeconfig.json"))

    echo @"
{
  "runtimeTarget": {
    "name": ".NETCoreApp,Version=v8.0",
    "signature": ""
  },
  "compilationOptions": {},
  "targets": {
    ".NETCoreApp,Version=v7.0": $(ConvertTo-Json -Depth 100 $targets)
  },
  "libraries": $(ConvertTo-Json -Depth 100 $libraries)
}
"@ > $([io.path]::Combine($dir, $filename + ".deps.json"))
}
