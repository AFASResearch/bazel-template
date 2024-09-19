load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResourceList",
)
load("@io_bazel_rules_dotnet//dotnet/private:actions/xaml.bzl", "xaml")
load("@io_bazel_rules_dotnet//dotnet/private:actions/conflict_resolution.bzl", "conflict_resolution_closure")

def _map_resource(d):
    return "\"" + d.result.path + "\"," + "\"" + d.identifier + "\""

# also lives in xaml.bzl
def _map_only_sourcegen(a):
    # sourcegenerator or sourcegeneration
    # ImportGenerator.dll
    # RegularExpressions.Generator.dll
    return a.path if a.path.endswith(".dll") and (a.path.endswith("Generator.dll") or a.path.find(".SourceGenerat") >= 0 or a.path.find(".sourcegenerat") >= 0 or a.path.find("/analyzers/") == -1) else None

def _job_args(dotnet, args):
    job_args = dotnet.actions.args()
    job_args.use_param_file("@%s", use_always = True)
    job_args.set_param_file_format("multiline")
    job_args.add_all(args)
    return job_args
    
def _only_srcs(p):
    return p.path if p.path.endswith(".cs") or p.path.endswith(".vb") else None

def emit_assembly_core(
        dotnet,
        name,
        target_type, # library or exe
        srcs,
        additional_files = None,
        deps = None,
        out = None,
        resources = None,
        defines = None,
        unsafe = False,
        data = None,
        keyfile = None,
        subdir = "./",
        server = None,
        args = []):
    """See dotnet/toolchains.rst#binary for full documentation."""

    if name == "" and out == None:
        fail("either name or out must be set")
    filename = out if out else name
    result = dotnet.declare_file(dotnet, path = subdir + filename)
    ref_result = dotnet.declare_file(dotnet, path = subdir + paths.split_extension(filename)[0] + ".ref.dll")
    # when server is specified pdb's have their pathmap substituted
    # otherwise only create a pdb in dbg mode
    pdb = dotnet.declare_file(dotnet, path = subdir + paths.split_extension(filename)[0] + ".pdb") if server or dotnet.debug else None # should we make this configurable in release?
    outputs = [result, ref_result] + ([pdb] if pdb else [])

    transitive_refs = depset(transitive = [d[DotnetLibrary].transitive_refs for d in deps["references"]])
    resource_items = [r for rs in resources for r in rs[DotnetResourceList].result]
    resource_files = [r.result for r in resource_items]

    runner_args = dotnet.actions.args()
    runner_args.add(target_type, format = "/target:%s")
    runner_args.add(result, format = "/out:\"%s\"")
    runner_args.add(ref_result, format = "/refout:\"%s\"")
    if pdb:
        runner_args.add(pdb, format = "/pdb:\"%s\"")
        runner_args.add("/debug:full")
    runner_args.add("/nostdlib")
    runner_args.add("/langversion:latest")
    runner_args.add("/nologo")
    runner_args.add("/deterministic+")
    runner_args.add("/define:NETCOREAPP")
    runner_args.add_all(defines, format_each = "/define:%s")
    runner_args.add_all(dotnet.no_warns, format_each = "/nowarn:%s")
    runner_args.add("/optimize%s" % ("-" if dotnet.debug else "+"))
    if unsafe:
        runner_args.add("/unsafe")
    if keyfile:
        runner_args.add("-keyfile:" + keyfile.files.to_list()[0].path)
    if dotnet.warn_as_error:
        runner_args.add("/warnaserror")

    transitive_analyzers = depset(transitive = [d[DotnetLibrary].transitive_analyzers for d in deps["references"]])
    transitive = depset(direct = deps["references"], transitive = [a[DotnetLibrary].transitive for a in deps["references"]])
    
    env = {
        # we disable multi level lookup of dotnet sdk during compilation
        # the dotnet runtime of the compiler is used as part of the deterministic key:
        # https://github.com/dotnet/roslyn/blob/main/docs/compilers/Deterministic%20Inputs.md
        "DOTNET_MULTILEVEL_LOOKUP": "0",
    }

    _format_ref_with_overrides = conflict_resolution_closure(deps["references"])

    if not dotnet.debug and dotnet.analyzer_ruleset:
        runner_args.add_all(transitive_analyzers, format_each = "/analyzer:\"%s\"")
        runner_args.add(dotnet.analyzer_ruleset, format = "/ruleset:\"%s\"")
        runner_args.add(dotnet.analyzer_config, format = "/analyzerconfig:\"%s\"")
        runner_args.add_all(dotnet.analyzer_additionalfiles, format_each = "/additionalfile:\"%s\"")
    else:
        runner_args.add_all(transitive_analyzers, map_each = _map_only_sourcegen, format_each = "/analyzer:\"%s\"")

    runner_args.add_all(transitive, allow_closure = True, map_each = _format_ref_with_overrides, format_each = "/reference:\"%s\"")

    runner_args.add_all(args)

    vb = "/nosdkpath" in args
    extra_srcs = [] if vb else dotnet.extra_srcs
    all_srcs = depset(transitive = [s.files for s in srcs + extra_srcs])

    if vb:
        runner_args.add('/nowarn')
    else:
        runner_args.add('/warn:0')

    (g_dir, g_resources) = xaml(dotnet, subdir, all_srcs, transitive, transitive_analyzers, transitive_refs, env, name, _format_ref_with_overrides)
    if g_dir:
        all_srcs = depset(direct = [g_dir], transitive = [all_srcs])
    if g_resources:
        resource_files.append(g_resources)
        resource_items.append(dotnet.new_resource(dotnet, name + ".g.resources", g_resources))

    runner_args.add_all(resource_items, format_each = "/resource:%s", map_each = _map_resource)

    # files could contain spaces. therefore quote
    runner_args.add_all(all_srcs, map_each = _only_srcs, format_each = '"%s"')

    additional_files = depset(transitive = [c.files for c in additional_files or []])
    runner_args.add_all(additional_files, format_each = '/additionalfile:"%s"')

    runner_args.use_param_file("@%s", use_always = True)
    runner_args.set_param_file_format("multiline")

    if server:
        # startup arguments of the server
        server_args = [dotnet.runner.path, dotnet.mcs.path]
        if dotnet.execroot_pathmap:
            server_args.append(dotnet.execroot_pathmap)

        # this ensures the action depends on runfiles tree creation even when --output_groups=-_hidden_top_level_INTERNAL_
        _, input_manifests = dotnet._ctx.resolve_tools(tools = [dotnet._ctx.attr.server])

        # Write csc params to file so wa can supply the file to the server
        paramfile = dotnet.declare_file(dotnet, path = name + ".csc.param")
        dotnet.actions.write(output = paramfile, content = runner_args)

        # Write a .Targets file for IDE integration to be picked up by MSBuild
        # It's probably better to implement this in a Bazel aspect in the future
        # https://docs.bazel.build/versions/master/skylark/aspects.html
        propsfilename = name + ".csproj.bazel.props"
        propsfile = dotnet.declare_file(dotnet, path = propsfilename)

        # TODO add references, analyzers & generated source files
        # & ruleset
        target_args = _job_args(dotnet, ["targets", propsfile])
        
        target_args.add_all(transitive_analyzers, format_each = "/analyzer:%s")
        target_args.add(dotnet.analyzer_ruleset, format = "/ruleset:%s")
        target_args.add(dotnet.analyzer_config, format = "/analyzerconfig:%s")
        target_args.add_all(dotnet.analyzer_additionalfiles, format_each = "/additionalfile:%s")
        target_args.add_all(transitive, allow_closure = True, map_each = _format_ref_with_overrides, format_each = "/reference:%s")
        # tod only add generated files
        target_args.add_all(args)

        dotnet.actions.run(
            inputs = [],
            env = env,
            input_manifests = input_manifests,
            outputs = [propsfile],
            executable = server,
            arguments = server_args + [target_args],
            mnemonic = "CoreCompile",
            execution_requirements = { "supports-multiplex-workers": "1", "no-cache": "1" },
            tools = [server],
            progress_message = (
                "Writing " + dotnet.label.package + "/obj/" + propsfilename
            )
        )
        
        # Our compiler server analyzes output dll's to prune the dependency graph
        unused_refs = dotnet.declare_file(dotnet, path = name + ".unused")
        dotnet.actions.run(
            # ensure propsfile is build when this action runs by making it an input
            inputs = depset(direct = [paramfile, propsfile] + resource_files, transitive = [all_srcs, transitive_refs, transitive_analyzers, additional_files]),
            env = env,
            input_manifests = input_manifests,
            outputs = outputs + [unused_refs],
            executable = server,
            arguments = server_args + [_job_args(dotnet, ["compile", paramfile.path, unused_refs.path, result.path])],
            mnemonic = "CoreCompile",
            execution_requirements = { "supports-multiplex-workers": "1" },
            # WARNING: this breaks caching because absolute paths are embedded in the pdb
            # tools = [server],
            progress_message = (
                "Compiling " + dotnet.label.package + ":" + dotnet.label.name
            ),
            unused_inputs_list = unused_refs
        )
    else:
        propsfile = None
        dotnet.actions.run(
            inputs = depset(direct = resource_files, transitive = [all_srcs, transitive_refs, transitive_analyzers]),
            env = env,
            outputs = outputs,
            executable = dotnet.runner,
            arguments = [dotnet.mcs.path, "/noconfig", runner_args],
            mnemonic = "CoreCompile",
            progress_message = (
                "Compiling " + dotnet.label.package + ":" + dotnet.label.name
            ),
        )
    # if not deps.get("propagate", []):
    #     fail(deps)

    return dotnet.new_library(
        dotnet = dotnet,
        name = name,
        deps = deps.get("propagate", deps["references"]),
        result = result,
        ref_result = ref_result,
        pdb = pdb,
        data = data,
        output_groups = [OutputGroupInfo(targets = [propsfile])] if propsfile else [],
    )
