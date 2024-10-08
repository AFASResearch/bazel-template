load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResource",
)
load("@core_sdk//:pathmap.bzl", "execroot_pathmap")

DotnetContext = provider()

def _declare_file(dotnet, path = None, ext = None, sibling = None):
    result = path if path else dotnet._ctx.label.name
    if ext:
        result += ext
    return dotnet.actions.declare_file(result, sibling = sibling)

def new_library(
    dotnet, name = None,
    version = None,
    deps = None,
    data = None,
    result = None,
    ref_result = None,
    pdb = None,
    libs = None,
    refs = None,
    analyzers = None,
    **kwargs
):
    if not libs:
        libs = [result] if result else []

    if not refs:
        if ref_result:
            refs = [ref_result]
        elif refs == None: # only use libs as refs when refs is not specified
            refs = libs

    if not all([type(f) == "File" for f in refs]):
        fail(refs)

    # Do not propagate netstandard deps
    if result and name.endswith(".SourceGenerator.Annotations"):
        deps = []

    transitive = depset(direct = deps, transitive = [a[DotnetLibrary].transitive for a in deps])
    transitive_refs = depset(direct = refs, transitive = [a[DotnetLibrary].transitive_refs for a in deps])
    transitive_analyzers = depset(direct = analyzers, transitive = [a[DotnetLibrary].transitive_analyzers for a in deps])
    runfiles = depset(
        direct = libs + ([pdb] if pdb else []),
        transitive = [a[DotnetLibrary].runfiles for a in deps] + (
            [t.files for t in data] if data else []
        )
    )

    # workaround: this should be a different rule
    if result and name.endswith(".SourceGenerator"):
        # For SourceGenerators we populate the /analyzer flags with our runfiles (result + pdb + deps runfiles)
        direct = libs

        for dep in deps:
            if dep[DotnetLibrary].name.lower() != "netstandard.library":
                direct.extend(dep[DotnetLibrary].libs)

        transitive_analyzers = depset(
            direct = direct,
            transitive =  [t.files for t in data] if data else []
        )

        # do not propagate deps (such as netstandard.library)
        transitive = depset()
        transitive_refs = depset(direct = refs)
        runfiles = depset()

    return DotnetLibrary(
        name = dotnet.label.name if not name else name,
        label = dotnet.label,
        deps = deps,
        transitive_refs = transitive_refs,
        transitive_analyzers = transitive_analyzers,
        transitive = transitive,
        result = result,
        libs = libs,
        refs = refs,
        ref_result = ref_result,
        pdb = pdb,
        runfiles = runfiles,
        version = version,
        **kwargs
    )

def _new_resource(dotnet, name, result, identifier = None, **kwargs):
    return DotnetResource(
        name = name,
        label = dotnet.label,
        result = result,
        identifier = result.basename if not identifier else identifier,
        **kwargs
    )

def dotnet_context(ctx, attr = None):
    if not attr:
        attr = ctx.attr

    context_data = attr.dotnet_context_data
    toolchain = ctx.toolchains[context_data._toolchain_type]

    return DotnetContext(
        # Fields
        label = ctx.label,
        toolchain = toolchain,
        actions = ctx.actions,
        assembly = toolchain.actions.assembly,
        resx = toolchain.actions.resx,
        runner = toolchain.dotnet_runner,
        mcs = toolchain.csc_binary,
        declare_file = _declare_file,
        new_library = new_library,
        new_resource = _new_resource,
        workspace_name = ctx.workspace_name,
        libVersion = context_data._libVersion,
        framework = context_data._framework,
        lib = context_data._lib,
        shared = context_data._shared,
        debug = ctx.var["COMPILATION_MODE"] == "dbg",
        extra_srcs = context_data._extra_srcs,
        no_warns = context_data._no_warns,
        analyzer_ruleset = context_data._analyzer_ruleset,
        analyzer_config = context_data._analyzer_config,
        analyzer_additionalfiles = context_data._analyzer_additionalfiles,
        warn_as_error = context_data._warn_as_error,
        host = context_data._host.files,
        execroot_pathmap = context_data._execroot_pathmap,
        _ctx = ctx,
    )

def _dotnet_context_data(ctx):
    return struct(
        _mcs_bin = ctx.attr.mcs_bin,
        _mono_bin = ctx.attr.mono_bin,
        _lib = ctx.attr.lib,
        _tools = ctx.attr.tools,
        _shared = ctx.attr.shared,
        _host = ctx.attr.host,
        _libVersion = ctx.attr.libVersion,
        _toolchain_type = ctx.attr._toolchain_type,
        _extra_srcs = ctx.attr.extra_srcs,
        _no_warns = ctx.attr.no_warns,
        _analyzer_ruleset = ctx.file.analyzer_ruleset,
        _analyzer_config = ctx.file.analyzer_config,
        _analyzer_additionalfiles = ctx.files.analyzer_additionalfiles,
        _warn_as_error = ctx.attr.warn_as_error,
        _framework = ctx.attr.framework,
        _execroot_pathmap = ctx.attr.execroot_pathmap if ctx.attr.execroot_pathmap else execroot_pathmap,
    )

core_context_data = rule(
    _dotnet_context_data,
    attrs = {
        "mcs_bin": attr.label(
            allow_files = True,
            default = "@core_sdk//:mcs_bin",
        ),
        "mono_bin": attr.label(
            allow_files = True,
            default = "@core_sdk//:mono_bin",
        ),
        "lib": attr.label(
            allow_files = True,
            default = "@core_sdk//:lib",
        ),
        "tools": attr.label(
            allow_files = True,
            default = "@core_sdk//:lib",
        ),
        "shared": attr.label(
            allow_files = True,
            default = "@core_sdk//:shared",
        ),
        "host": attr.label(
            allow_files = True,
            default = "@core_sdk//:host",
        ),
        "libVersion": attr.string(
            default = "",
        ),
        "framework": attr.string(
            default = "",
        ),
        "_toolchain_type": attr.string(
            default = "@io_bazel_rules_dotnet//dotnet:toolchain_core",
        ),
        "extra_srcs": attr.label_list(
            allow_files = True,
            default = [],
        ),
        "no_warns": attr.string_list(
            default = [],
        ),     
        "analyzer_ruleset": attr.label(
            default = None,
            allow_single_file = True,
        ),
        "analyzer_config": attr.label(
            default = None,
            allow_single_file = True,
        ),        
        "warn_as_error": attr.bool(
            default = False,
        ),        
        "analyzer_additionalfiles": attr.label_list(
            default = [],
            allow_files = True,
        ),        
        "execroot_pathmap": attr.string(
            default = "",
        ),        
    },
)
