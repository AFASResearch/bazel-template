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
    "launcher_header"
)
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_dotnet//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition", "netstandard_transition")

# DotnetContext, DotnetLibrary
def create_launcher(dotnet, library, shim = None):
    launch_target = shim if shim else library.result
    launcher = dotnet.declare_file(dotnet, path = "launcher.bat", sibling = launch_target)
    dotnet.actions.write(
        output = launcher,
        content = launcher_header(dotnet._ctx, {
            "DOTNET_RUNNER": dotnet.runner,
        }) + r"""
set DOTNET_ROOT=%DOTNET_RUNNER%\..
"%~dp0{launch_target}" %*
""".format(
    launch_target = launch_target.basename))

    # DllName.runtimeconfig.json
    runtimeconfig = write_runtimeconfig(dotnet._ctx, launch_target, True, dotnet._ctx.attr.runtime_properties)
    # DllName.deps.json
    depsjson = write_depsjson(dotnet, library)
    # ManifestLoader
    loader = dotnet.actions.declare_file("ManifestLoader.dll", sibling = library.result)
    dotnet.actions.symlink(output = loader, target_file = dotnet._ctx.attr.loader[DotnetLibrary].result)

    runfiles = dotnet._ctx.runfiles(
        files = [launch_target, dotnet.runner, launcher, runtimeconfig, depsjson, loader], 
        transitive_files = depset(
            transitive = [library.runfiles, dotnet.host]
        )
    )

    return DefaultInfo(
        files = depset([library.result]),
        runfiles = runfiles,
        executable = launcher,
    )

# copies apphost.exe and embeds target dll path to dllname.exe
def create_shim_exe(ctx, dll):
    exe = ctx.actions.declare_file(paths.replace_extension(dll.basename, ".exe"), sibling = dll)
    args = ctx.actions.args()
    args.add(ctx.file._shim_script)
    args.add_joined(ctx.files._shim_deps, join_with = ',')
    args.add(ctx.file._apphost)
    args.add(exe, format = "\"%s\"")
    args.add(dll, format = "\"%s\"")

    ctx.actions.run(
        executable = 'powershell',
        arguments = [args],
        inputs = [ctx.file._shim_script, ctx.file._apphost, dll] + ctx.files._shim_deps,
        outputs = [exe],
    )

    return exe

def _rule(target_type, 
    server_default = Label("@io_bazel_rules_dotnet//tools/server:Compiler.Server.Multiplex"),
    loader_default = Label("@io_bazel_rules_dotnet//tools/loader:ManifestLoader"),
    vb = False):

    def _rule_impl(ctx):
        """_rule_impl emits actions for compiling executable assembly."""
        dotnet = dotnet_context(ctx)
        name = ctx.label.name
        
        args = [] + ctx.attr.compilation_args

        if ctx.attr.imports:
            args.append("/imports:%s" % (",".join(ctx.attr.imports)))
        if ctx.attr.nullable:
            args.append("/nullable")

        # TODO https://github.com/philippgille/docs-1/blob/master/docs/csharp/language-reference/compiler-options/listed-alphabetically.md
        # args.append('/platform:x64')
        # args.append('/highentropyva+')
        # args.append('/errorreport:prompt')

        if vb:
            # TODO get rid of /pdb
            args.append('/vbruntime:external/nuget.microsoft.netcore.app.ref.v8.0.0/ref/net8.0/Microsoft.VisualBasic.dll')
            args.append('/define:"CONFIG=\\"Release\\",TRACE=-1,_MyType=\\"Empty\\""')
            args.append('/filealign:512')
            args.append('/nosdkpath')

            # https://learn.microsoft.com/en-us/dotnet/visual-basic/reference/command-line-compiler/imports
            args.append('/imports:Microsoft.VisualBasic,System,System.Collections,System.Collections.Generic,System.Diagnostics,System.Linq,System.Xml.Linq,System.Threading.Tasks')
            args.append('/rootnamespace:%s' % (ctx.attr.root_namespace))
            args.append('/optioncompare:Binary') # Specifies how string comparisons are made.
            args.append('/optionexplicit+') # Causes the compiler to report errors if variables are not declared before they are used.
            args.append('/optionstrict:custom') # Enforces strict type semantics to restrict implicit type conversions.
            args.append('/optioninfer+') # Enables the use of local type inference in variable declarations.
        else:
            args.append("/fullpaths")
            args.append("/define:TRACE;%s" % ("DEBUG" if dotnet.debug else "RELEASE"))

        assembly = dotnet.assembly(
            dotnet,
            name = name,
            target_type = ctx.attr.target_type,
            srcs = ctx.attr.srcs,
            additional_files = ctx.attr.additional_files,
            deps = ctx.split_attr.deps,
            resources = ctx.attr.resources,
            out = ctx.attr.out,
            defines = ctx.attr.defines,
            data = ctx.attr.data,
            unsafe = ctx.attr.unsafe,
            keyfile = ctx.attr.keyfile,
            server = ctx.executable.server,
            args = args
        )

        result = [assembly] + assembly.output_groups
        if ctx.attr.target_type != "library":
            shim = create_shim_exe(ctx, assembly.result)
            result.append(create_launcher(dotnet, assembly, shim))
        else:
            # always output a DefaultInfo with a file so directly building this target will trigger actions
            result.append(DefaultInfo(
                files = depset([assembly.result]),
            ))

        return result

    return rule(
        _rule_impl,
        attrs = {
            "deps": attr.label_list(providers = [DotnetLibrary], cfg = tfm_transition),
            "_allowlist_function_transition": attr.label(
                default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
            ),
            "resources": attr.label_list(providers = [DotnetResourceList]),
            "compilation_args": attr.string_list(default = []),
            "srcs": attr.label_list(allow_files = [".vb" if vb else ".cs"]),
            "xamls": attr.label_list(allow_files = [".xaml"]),
            "xaml_resources": attr.label_list(allow_files = True),
            "additional_files": attr.label_list(default = [], allow_files = True),
            "runtime_properties": attr.string_dict(allow_empty=True, default={}, mandatory=False),
            "out": attr.string(),
            # root namespace is only used for VB
            "root_namespace": attr.string(default = "Afas"),
            # imports are only used for VB
            "imports": attr.string_list(),
            "defines": attr.string_list(),
            "unsafe": attr.bool(default = False),
            "nullable": attr.bool(default = False),
            "data": attr.label_list(allow_files = True),
            "keyfile": attr.label(allow_files = True),
            "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:core_context_data")),
            "server": attr.label(
                default = server_default,
                executable = True,
                cfg = "exec",
            ),
            "markup": attr.label(
                default = None if server_default == None else Label("@io_bazel_rules_dotnet//tools/markup"),
                executable = True,
                cfg = "exec",
            ),
            "loader": attr.label(
                default = loader_default,
                executable = False,
                cfg = "target"
            ),
            "target_type": attr.string(default = target_type),
            "simpleresgen": attr.label(default = None if server_default == None else Label("@io_bazel_rules_dotnet//tools/simpleresgen:simpleresgen")),
            
            # Shim dependencies
            "_apphost": attr.label(default = "@core_sdk//:sdk/current/AppHostTemplate/apphost.exe", allow_single_file = True),
            "_shim_script": attr.label(default = "@io_bazel_rules_dotnet//dotnet/private:shim.ps1", allow_single_file = True),
            "_shim_deps": attr.label_list(providers = [DotnetLibrary], default = ["@rules_dotnet_nuget_packages//system.memory", "@rules_dotnet_nuget_packages//microsoft.net.hostmodel"], cfg = netstandard_transition),
        },
        toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_core"],
        executable = target_type == "exe",
    )

core_library = _rule("library")
core_binary = _rule("exe")
vb_library = _rule("library", vb = True)
vb_binary = _rule("exe", vb = True)
core_library_no_server = _rule("library", None, None)
core_binary_no_server = _rule("exe", None)
