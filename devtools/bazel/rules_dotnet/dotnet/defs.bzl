load(
    "@io_bazel_rules_dotnet//dotnet/private:context.bzl",
    _core_context_data = "core_context_data",
    _dotnet_context = "dotnet_context",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:rules/binary.bzl",
    _core_binary = "core_binary",
    _core_library = "core_library",
    _vb_binary = "vb_binary",
    _vb_library = "vb_library",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:rules/resx.bzl",
    _core_resx = "core_resx",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:rules/resource.bzl",
    _core_resource = "core_resource",
    _core_resource_multi = "core_resource_multi",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:rules/import.bzl",
    _core_import_binary = "core_import_binary",
    _core_import_library = "core_import_library",
)

# We implicitly add the aspnetcore.app.ref package if the netcore.app.ref package is present fore core_* targets
def core_binary(deps, **kwargs):
    if "@nuget//microsoft.aspnetcore.app.ref" not in deps and "@nuget//microsoft.netcore.app.ref" in deps:
        deps = ["@nuget//microsoft.aspnetcore.app.ref"] + deps

    _core_binary(deps = deps, **kwargs)
def core_library(deps, **kwargs):
    if "@nuget//microsoft.aspnetcore.app.ref" not in deps and "@nuget//microsoft.netcore.app.ref" in deps:
        deps = ["@nuget//microsoft.aspnetcore.app.ref"] + deps
        
    _core_library(deps = deps, **kwargs)

vb_binary = _vb_binary
vb_library = _vb_library
dotnet_context = _dotnet_context
core_resx = _core_resx
core_resource = _core_resource
core_resource_multi = _core_resource_multi
core_import_binary = _core_import_binary
core_import_library = _core_import_library
core_context_data = _core_context_data
