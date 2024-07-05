$bin = [IO.Path]::Combine($env:USERPROFILE, "bazel")

Write-Host "Attempting to install Bazel to $bin"

function dirNotExists {
	return !(Test-Path $args[0] -PathType Container)
}

function fileNotExists {
	return !(Test-Path $args[0] -PathType Leaf)
}
function exeExists {
	return (Get-Command $args[0] -ErrorAction SilentlyContinue)
}
function refreshPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") +
                ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

if(dirNotExists $bin)
{
	mkdir $bin | Out-Null
}

# Ensure %USERPROFILE%/bin is in Path
$user_env = [Environment]::GetEnvironmentVariable("Path", "User").Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)
if(!$user_env.Contains($bin))
{
	Write-Host "Adding '$bin' to user Path environment variable"
	$user_env += $bin
	[Environment]::SetEnvironmentVariable("Path", [String]::Join(";", $user_env), "User")
	refreshPath
}

function download {
	$url = $args[0]
	$file = Split-Path $url -Leaf
	$output = [IO.Path]::Combine($bin, $file)
	if(![IO.File]::Exists($output))
	{
		Write-Host "Downloading '$url' to '$output'"
		(New-Object System.Net.WebClient).DownloadFile($url, $output)
	}
	else
	{
		Write-Host "'$output' already exists"
	}
	return $output
}
function updateSymlink {
	$symlink = $args[0]
	$target = $args[1]

	$exists = [IO.File]::Exists($symlink)
	$is_symlink = $exists -and (Get-Item $symlink).LinkType -eq "SymbolicLink"
	
	if($exists -and !$is_symlink)
	{
		Write-Warning "The '$symlink' file exists and is not a symlink. We did not update it to '$target'"
	}
	else
	{
		if($is_symlink)
		{
			Write-Host "Removing existing '$symlink' symlink"
			Remove-Item $symlink
		}
	
		Write-Host (cmd.exe /C "mklink ""$symlink"" ""$target""" *>&1)
	}
}

if(exeExists "bazel")
{
	$path = (Get-Command bazel).Source
	Write-Warning "The bazel command seems to be installed already at $path"
	Write-Warning "Please ensure that this is a Bazelisk installation"
}
else
{
	# $bazel_bin = download "https://github.com/bazelbuild/bazel/releases/download/3.1.0/bazel-3.1.0-windows-x86_64.exe"
	# We use bazelisk instead. This allows us to manage the bazel version inside our repo
	$bazel_bin = download "https://github.com/bazelbuild/bazelisk/releases/download/v1.4.0/bazelisk-windows-amd64.exe"
	$bazel_symlink = [IO.Path]::Combine($bin, "bazel.exe")
	updateSymlink $bazel_symlink $bazel_bin	
}

download "https://github.com/bazelbuild/buildtools/releases/download/3.4.0/buildifier.exe" | Out-Null
download "https://github.com/bazelbuild/buildtools/releases/download/3.4.0/buildozer.exe" | Out-Null

if(!$env:BAZEL_SH)
{
	$gitBash = "C:\Program Files\Git\bin\bash.exe"
	if(exeExists $gitBash)
	{
		Write-Host "Setting BAZEL_SH environment variable to '$gitBash'"
		[Environment]::SetEnvironmentVariable("BAZEL_SH", $gitBash, "User")
		$env:BAZEL_SH = $gitBash
	}
	else
	{
		Write-Warning "Could not set BAZEL_SH environment variable because '$gitBash' was not found."
	}
}
else
{
	Write-Host "BAZEL_SH environment variable already set to '$env:BAZEL_SH'"
}

if(fileNotExists "$PSScriptRoot\..\..\.git\hooks\commit-msg")
{
	Copy-Item "$PSScriptRoot\..\..\.githooks\commit-msg" "$PSScriptRoot\..\..\.git\hooks\commit-msg"
	Write-Host "git hook commit-msg installed"
}
else
{
	Write-Host "git hook commit-msg already installed"
}

bazel run @nodejs_windows_amd64//:bin/npm.cmd -- install -g vsts-npm-auth
bazel run @nodejs_windows_amd64//:bin/nodejs/vsts-npm-auth.cmd -- -config .npmrc
iex "& { $(irm https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx"

$devtools = "C:\Development Tools"
$batbat = "$devtools\BAT.bat"

if(dirNotExists $devtools)
{
	mkdir $devtools | Out-Null
}
elseif(fileNotExists $batbat)
{
	cp "\\ad.afas.nl\ai\Development Tools\BAT\BAT.bat" $devtools
}

& $batbat
