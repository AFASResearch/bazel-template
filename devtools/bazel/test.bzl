"""
Here we implement a test rule for testing .Net Core projects
It is based on the rules found in rules_dotnet but calls dotnet.exe directly
This is because the nunit console runner does not (yet) support .Net Core
"""

load(
    "@io_bazel_rules_dotnet//dotnet/private:context.bzl",
    "dotnet_context",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResourceList",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:json.bzl",
    "write_runtimeconfig",
    "write_depsjson",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:runfiles.bzl",
    "launcher_header",
)

load("@bazel_skylib//lib:paths.bzl", "paths")
load("//devtools/bazel:common_settings.bzl", "BuildSettingInfo")
load("@rules_dotnet//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _unit_test(ctx):
    dotnet = dotnet_context(ctx, struct(
        # due to our test_transition dotnet_context_data becomes a list
        dotnet_context_data = ctx.attr.dotnet_context_data[0],
    ))
    name = ctx.label.name

    # Compile the test DLL
    testdll = dotnet.assembly(
        dotnet,
        name = name,
        srcs = ctx.attr.srcs,
        additional_files = ctx.attr.additional_files,
        deps = ctx.attr.deps,
        resources = ctx.attr.resources,
        out = ctx.attr.out,
        defines = ctx.attr.defines,
        unsafe = ctx.attr.unsafe,
        data = ctx.attr.data,
        target_type = "library",
        keyfile = ctx.attr.keyfile,
        server = ctx.executable.server,
        args = ["/nullable"] if ctx.attr.nullable else [],
    )

    logger = ctx.attr.logger[0][DotnetLibrary]

    # Write a bat launcher test.bat that starts the test run
    launcher = dotnet.declare_file(dotnet, path = "launcher.bat")
    ctx.actions.write(
        output = launcher,
        content = launcher_header(ctx, {
            "DOTNET_RUNNER": dotnet.runner,
            # "DOTCOVER": ctx.file.dotcover,
        }) + r"""
SET DOTNET_CLI_HOME=/Users/%USER%

SETLOCAL DISABLEDELAYEDEXPANSION
if "%TESTBRIDGE_TEST_ONLY%" neq "" (
    SET FILTER=--filter "%TESTBRIDGE_TEST_ONLY%"
) else (
    SET FILTER=--filter "TestCategory != BazelExclude & TestCategory != NightlyBuild & TestCategory != Conversion"
)
SET TARGET_ARGS=test %FILTER% --logger junit;LogFilePath=%XML_OUTPUT_FILE% %~dp0/{dll_path}

SET WinDir=C:\Windows
SET ProgramData=C:\ProgramData

if "{enable_coverage}"=="true" (
    "%DOTCOVER%" cover /Output="%TEST_UNDECLARED_OUTPUTS_DIR%/coverage.dcvr" /TargetExecutable="%DOTNET_RUNNER%" /TargetArguments="%TARGET_ARGS:"=""%" /AttributeFilters=System.Diagnostics.CodeAnalysis.ExcludeFromCodeCoverageAttribute
) else (
    "%DOTNET_RUNNER%" %TARGET_ARGS%
)
""".format(
    enable_coverage = "true" if ctx.attr.enable_dotcover[BuildSettingInfo].value else "false",
    dll_path = testdll.result.basename))

    # DllName.runtimeconfig.json
    runtimeconfig = write_runtimeconfig(dotnet, testdll.result)
    # DllName.deps.json
    depsjson = write_depsjson(dotnet, testdll)
    # ManifestLoader
    loader = dotnet.actions.declare_file("ManifestLoader.dll", sibling = testdll.result)
    dotnet.actions.symlink(output = loader, target_file = dotnet._ctx.attr.loader[DotnetLibrary].result)

    symlinks = {}
    local_folder = paths.dirname(ctx.build_file_path)
    for f in testdll.runfiles.to_list() + logger.libs:
        # Local test data must also be moved up relatively
        if f.path.startswith(local_folder):
            symlinks[paths.relativize(f.path, local_folder)] = f
        # Additional symlink for testhost.dll next to {test}.dll
        elif f.basename == "testhost.dll":
            symlinks[f.basename] = f
        # TestAdapters
        elif f.basename.endswith("TestAdapter.dll"):
            symlinks[f.basename] = f
        elif f.basename.endswith("TestLogger.dll"):
            symlinks[f.basename] = f

    # the current set of symlinks is local data. We also link them next to our output dll
    symlink_files = []
    for path, file in symlinks.items():
        f = ctx.actions.declare_file(path)
        ctx.actions.symlink(output = f, target_file = file)
        symlink_files.append(f)

    # additional symlinks to work under the runfiles folder
    for f in [
        # Due to path length limitations we cannot rely on the nested runfiles tree
        # Therefore we symlink in the root cwd which currently is short enough
        testdll.result, runtimeconfig, depsjson,
    ]:
        symlinks[f.basename] = f

    # Also link pdb next to dll for debugging
    if testdll.pdb:
        symlinks[testdll.pdb.basename] = testdll.pdb

    runfiles = ctx.runfiles(
        files = [
            launcher, runtimeconfig, depsjson, loader,
            dotnet.runner, 
            # ctx.file.dotcover, 
            ctx.file.host_package, ctx.file.frontend_schema] + 
            [dll for dll in testdll.transitive_analyzers.to_list() if dll.path.endswith("SourceGenerator.dll")],
        transitive_files = depset(
            transitive = [
                testdll.runfiles,
                logger.runfiles,
                dotnet.host,

                # SourceGenerator tests also need to resolve analyzers at runtime
                # testdll.transitive_analyzers,
            ]
        ),
        symlinks = symlinks,
    )

    return [
        testdll,
        DefaultInfo(
            files = depset([testdll.result, launcher, runtimeconfig, depsjson, loader] + symlink_files),
            runfiles = runfiles,
            executable = launcher,
        ),
    ] + testdll.output_groups

# We wish to configure a different analyzer ruleset in test compilations
def _test_transition_impl(settings, attr):
    return {"//:target_context": "test"}

test_transition = transition(
    implementation = _test_transition_impl,
    inputs = [],
    outputs = ["//:target_context"]
)

_core_nunit3_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary], cfg = tfm_transition),
        "resources": attr.label_list(providers = [DotnetResourceList]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "additional_files": attr.label_list(default = [], allow_files = True),
        "host_package": attr.label(default = "//host:host_package", allow_single_file = True),
        "frontend_schema": attr.label(default = "@//:frontend_schema", allow_single_file = True),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "nullable": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:core_context_data"), cfg = test_transition),
        # required for test_transition
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
        "server": attr.label(
            default = Label("@io_bazel_rules_dotnet//tools/server:Compiler.Server.Multiplex"),
            executable = True,
            cfg = "host",
        ),
        "loader": attr.label(
            default = Label("@io_bazel_rules_dotnet//tools/loader:ManifestLoader"),
            executable = False,
            cfg = "target"
        ),
        "native_deps": attr.label(default = Label("@core_sdk//:native_deps")),
        "keyfile": attr.label(allow_files = True),
        "logger": attr.label(default = "@nuget//junittestlogger", cfg = tfm_transition),
        # "dotcover": attr.label(default = "@nuget//jetbrains.dotcover.commandlinetools:current/tools/dotCover.exe", allow_single_file = True),
        "enable_dotcover": attr.label(default = "//:enable_dotcover"),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_core"],
    executable = False,
    test = True,
)

def core_nunit3_test(deps, **kwargs):
    if "@nuget//microsoft.aspnetcore.app.ref" not in deps and "@nuget//microsoft.netcore.app.ref" in deps:
        deps = ["@nuget//microsoft.aspnetcore.app.ref"] + deps

    _core_nunit3_test(deps = deps, **kwargs)
