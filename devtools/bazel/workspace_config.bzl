"""
Currently there is no way to determine workspace root during tests
Repository rules however support resolving absolute paths
"""

def _workspace_config_repo_impl(ctx):
  ctx.file("workspace.ps1", r"""
$ErrorActionPreference = "Stop"
# Old versions of powershell do not fix casing of (gi path).FullName. We fix this here since this is required for hot reloading
function fix($path) {{
  $parent = Split-Path $path;
  if($parent -eq "")
  {{
    return $path;
  }}
  $leaf = Split-Path -Leaf $path;
  return Join-Path (fix $parent) (Get-ChildItem $parent -Filter $leaf);
}}

[System.IO.File]::WriteAllText("$pwd\workspace.bzl", @"
ANTA_ROOT="$((fix {anta}) -replace '\\','\\')"
"@);
""".format(anta = repr(str(ctx.path(ctx.workspace_root).dirname))))

  exit = ctx.execute(["powershell", "-File", "workspace.ps1"])
  if exit.return_code != 0:
    fail(exit.stderr + "\n" + exit.stdout)

  ctx.file("BUILD", r"""exports_files(["workspace.bzl"])
""")

workspace_config_repo = repository_rule(
    _workspace_config_repo_impl,
    attrs = {
        "workspace": attr.label(default = "//:.gitattributes"),
    },
    local = True,
    environ = ["COMPUTERNAME", "USERDNSDOMAIN", "USERPROFILE"]
)
