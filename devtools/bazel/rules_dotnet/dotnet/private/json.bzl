"""
  Write DllName.deps.json
  Write DllName.runtimeconfig.json
"""

load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
)
load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
  "@core_sdk//:version.bzl",
  "framework_version",
  "tfm"
)

def _assembly_name(name):
    return paths.split_extension(name)[0]

def _quote(s):
    return "\"" + s + "\""

def _repr(v):
  if v == "true":
    return True
  if v == "false":
    return False
  return v

def write_runtimeconfig(ctx, dll_file, manifestloader = True, runtime_properties = {}):
    if type(dll_file) == "File":
      name = dll_file.basename
      file = dll_file
    else:
      name = dll_file
      file = None

    runtimeconfig = ctx.actions.declare_file(_assembly_name(name) + ".runtimeconfig.json", sibling = file)

    loose_framework_version = "{}.0.0".format(framework_version.split(".")[0])

    properties = { k: _repr(v) for k, v in runtime_properties.items() }
    if manifestloader:
      properties["STARTUP_HOOKS"] = "ManifestLoader"

    ctx.actions.write(runtimeconfig, json.encode_indent({
      "runtimeOptions": {
        "tfm": tfm,
        "frameworks": [{
          "name": d[DotnetLibrary].name[:-4],
          "version": loose_framework_version
        } for d in ctx.attr.deps if d[DotnetLibrary].name.endswith(".Ref")],
        "configProperties": properties
      },
    }, indent = '  '))
    return runtimeconfig

def write_depsjson(dotnet_ctx, library):
    short_framework_version = ".".join(framework_version.split(".")[:2])

    json = r"""
{
  "runtimeTarget": {
    "name": ".NETCoreApp,Version=v"""+ short_framework_version +r""""
  },
  "targets": {
    ".NETCoreApp,Version=v"""+ short_framework_version +r"""": {
      "ManifestLoader": {
        "runtime": { "ManifestLoader.dll": {"assemblyVersion":"1.0.0.0","fileVersion":"1.0.0.0"} }
      }
    }
  },
  "libraries": {
    "ManifestLoader": {
      "type": "package",
      "serviceable": true,
      "sha512": "",
      "path": ""
    }
  }
}
"""

    depsjson = dotnet_ctx.declare_file(dotnet_ctx, path = _assembly_name(library.result.basename) + ".deps.json", sibling = library.result)
    dotnet_ctx.actions.write(depsjson, json)
    return depsjson