"""
Defines core_publish
"""

load("@io_bazel_rules_dotnet//dotnet/private:providers.bzl", "DotnetLibrary")
load("@bazel_skylib//lib:paths.bzl", "paths")

def _unsupported(f):
    # This is a workaround
    # 1) conflict resolution in BazelDotnet should resolve this
    # But because it works on package names it failes to recognize
    # BouncyCastle.Crypto.dll is in bouncycastle.netcore and portable.bouncycastle
    # Microsoft.TestPlatform.CoreUtilities.dll is in microsoft.testplatform.testhost and microsoft.testplatform.objectmodel
    # 2) there are multiple files with the same name in Afas.Host.Runtime that we flatten
    # 3) testhost.dll is referenced multiple times
    return (f.path.find("microsoft.testplatform.objectmodel") != -1 or 
           f.path.find("bouncycastle.netcore") != -1 or 
           f.path.endswith("testhost.dll") or 
           f.path.find("/build/") != -1)

def _core_publish_impl(ctx):
    directory = ctx.actions.declare_directory(ctx.attr.name)

    overrides = [d[DotnetLibrary].targeting_pack_overrides for lib in ctx.attr.libraries for d in lib[DotnetLibrary].deps if hasattr(d[DotnetLibrary], 'targeting_pack_overrides')]

    def has_override(provider):
        if provider.version:
            version = [int(v) for v in provider.version.split("-", 2)[0].split(".", 3)]

            for o in overrides:
                override_version = o.get(provider.name.lower(), None)
                if override_version and override_version >= version:
                    return True
        return False

    def map_dep(dep):
        provider = dep[DotnetLibrary]

        if(has_override(provider)):
            return None
        
        return json.encode({
            "name": provider.name,
            "version": provider.version or "1.0.0-pre",
            "files": [f.path for f in provider.libs + ([provider.pdb] if provider.pdb else []) if not _unsupported(f)],
            "dependencies": { d[DotnetLibrary].name: d[DotnetLibrary].version or "1.0.0-pre" for d in provider.deps },
            "type": "package" if provider.version else "project",
        })
        
    def map_runfile(f):
        if f.path.find("Afas.Host.Runtime") != 1 and f.extension.lower() == "json":
            if f.basename not in ["tenantconfig.json", "appsettings.json"]:
                return None
        
        if f.path.endswith(".pdb"):
            return None
        
        if f.path.endswith(".dll"):
            return None

        return f.path

    runfiles = depset(transitive = [lib[DotnetLibrary].runfiles for lib in ctx.attr.libraries])
    runfiles_arg = ctx.actions.args()
    runfiles_arg.add_all(depset(ctx.attr.libraries, transitive = [lib[DotnetLibrary].transitive for lib in ctx.attr.libraries]), allow_closure = True, map_each = map_dep, uniquify = True)
    runfiles_arg.add_all(runfiles, allow_closure = True, map_each = map_runfile)
    runfiles_arg.use_param_file("@%s", use_always = True)
    runfiles_arg.set_param_file_format("multiline")

    runfiles_file = ctx.actions.declare_file(ctx.attr.name + ".runfiles.param")
    ctx.actions.write(output = runfiles_file, content = runfiles_arg)

    args = ctx.actions.args()
    args.add(ctx.file.publish)

    args.add("-hostmodel")
    args.add(ctx.file.hostmodel)
    args.add("-apphost")
    args.add(ctx.file.apphost)
    args.add("-dir")
    args.add(directory.path)
    args.add("-entrypoints")
    args.add_joined([lib[DotnetLibrary].result for lib in ctx.attr.libraries], join_with = ",")
    args.add("-runfiles")
    args.add(runfiles_file)

    ctx.actions.run(
        executable = "pwsh.exe",
        arguments = [args],
        inputs = depset([ctx.file.publish, ctx.file.hostmodel, ctx.file.apphost, runfiles_file], transitive = [runfiles]),
        outputs = [directory],
    )

    lib = ctx.attr.libraries[0]
    exe_name = paths.replace_extension(lib[DotnetLibrary].result.basename, ".exe")
    exe_path = ctx.attr.name + "/" + exe_name
    launcher = ctx.actions.declare_file(exe_name + ".bat")
    ctx.actions.write(
            output = launcher,
            is_executable = True,
            content = "%~dp0" + exe_path + " %*")

    return [
        DefaultInfo(
            files = depset([directory]),
            executable = launcher
        ),
    ]

core_publish = rule(
    _core_publish_impl,
    attrs = {
        "libraries": attr.label_list(providers = [DotnetLibrary]),
        "hostmodel": attr.label(default = "@nuget//microsoft.net.hostmodel", allow_single_file = True),
        "apphost": attr.label(default = "@core_sdk//:sdk/current/AppHostTemplate/apphost.exe", allow_single_file = True),
        "publish": attr.label(default = "//devtools/bazel:publish.ps1", allow_single_file = True),
    },
    executable = True
)

def _c_transition_impl(settings, attr):
    return [
        { "//command_line_option:compilation_mode": "opt" },
        { "//command_line_option:compilation_mode": "dbg" },
    ]

c_transition = transition(
    implementation = _c_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
    ]
)

def _opt_dbg_transition_impl(ctx):
    return DefaultInfo(files = depset(ctx.files.target))

opt_dbg_transition = rule(
    _opt_dbg_transition_impl,
    attrs = {
        "target": attr.label(allow_files = True, cfg = c_transition),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
