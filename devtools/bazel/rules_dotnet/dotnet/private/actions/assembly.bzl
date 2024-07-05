load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResourceList",
)

def _map_resource(d):
    return d.result.path + "," + d.identifier

def _map_only_sourcegen(a):
    # sourcegenerator or sourcegeneration
    # ImportGenerator.dll
    # RegularExpressions.Generator.dll
    return a.path if a.path.endswith(".dll") and (a.path.endswith("Generator.dll") or a.path.find(".SourceGenerat") >= 0 or a.path.find(".sourcegenerat") >= 0 or a.path.find("/analyzers/") == -1) else None

def _make_runner_arglist(dotnet, deps, resources, output, ref_output, debug, pdb, target_type, defines, unsafe, keyfile):
    args = dotnet.actions.args()

    args.add(target_type, format = "/target:%s")
    args.add(output, format = "/out:%s")
    args.add(ref_output, format = "/refout:%s")
    if pdb:
        args.add(pdb, format = "/pdb:%s")
        args.add("/debug:full")

    args.add("/nostdlib")
    args.add("/langversion:latest")
    args.add("/nologo")
    args.add("/deterministic+")
    args.add("/define:NETCOREAPP")
    args.add_all(defines, format_each = "/define:%s")
    args.add_all(dotnet.no_warns, format_each = "/nowarn:%s")

    if debug:
        args.add("/optimize-")
    else:
        args.add("/optimize+")
    
    if unsafe:
        args.add("/unsafe")
    if keyfile:
        args.add("-keyfile:" + keyfile.files.to_list()[0].path)
    if dotnet.warn_as_error:
        args.add("/warnaserror")

    args.add_all(resources, format_each = "/resource:%s", map_each = _map_resource)

    return args

def _job_args(dotnet, args):
    job_args = dotnet.actions.args()
    job_args.use_param_file("@%s", use_always = True)
    job_args.set_param_file_format("multiline")
    job_args.add_all(args)
    return job_args
    
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

    transitive_analyzers = depset(transitive = [d[DotnetLibrary].transitive_analyzers for d in deps])
    transitive_refs = depset(transitive = [d[DotnetLibrary].transitive_refs for d in deps])
    resource_items = [r for rs in resources for r in rs[DotnetResourceList].result]
    resource_files = [r.result for r in resource_items]
    runner_args = _make_runner_arglist(dotnet, deps, resource_items, result, ref_result, dotnet.debug, pdb, target_type, defines, unsafe, keyfile)

    transitive_analyzers = depset(transitive = [d[DotnetLibrary].transitive_analyzers for d in deps])
    transitive = depset(direct = deps, transitive = [a[DotnetLibrary].transitive for a in deps])
    overrides = [d[DotnetLibrary].targeting_pack_overrides for d in deps if hasattr(d[DotnetLibrary], 'targeting_pack_overrides')]
    
    def _format_ref_with_overrides(assembly):
        provider = assembly[DotnetLibrary]

        if provider.version:
            version = [int(v) for v in provider.version.split("-", 2)[0].split(".", 3)]

            for o in overrides:
                override_version = o.get(provider.name.lower(), None)
                if override_version and override_version >= version:
                    return None

                # TODO we should cause the targeting pack to be dropped in the else case

        return [f.path for f in provider.refs]

    if not dotnet.debug and dotnet.analyzer_ruleset:
        runner_args.add_all(transitive_analyzers, format_each = "/analyzer:%s")
        runner_args.add(dotnet.analyzer_ruleset, format = "/ruleset:%s")
        runner_args.add(dotnet.analyzer_config, format = "/analyzerconfig:%s")
        runner_args.add_all(dotnet.analyzer_additionalfiles, format_each = "/additionalfile:%s")
    else:
        runner_args.add_all(transitive_analyzers, map_each = _map_only_sourcegen, format_each = "/analyzer:%s")

    runner_args.add_all(transitive, allow_closure = True, map_each = _format_ref_with_overrides, format_each = "/reference:%s")

    runner_args.add_all(args)

    all_srcs = depset(transitive = [s.files for s in srcs + dotnet.extra_srcs])
    # files could contain spaces. therefore quote
    runner_args.add_all(all_srcs, format_each = '"%s"')

    additional_files = depset(transitive = [c.files for c in additional_files or []])
    runner_args.add_all(additional_files, format_each = '/additionalfile:"%s"')

    runner_args.use_param_file("@%s", use_always = True)
    runner_args.set_param_file_format("multiline")

    env = {
        # we disable multi level lookup of dotnet sdk during compilation
        # the dotnet runtime of the compiler is used as part of the deterministic key:
        # https://github.com/dotnet/roslyn/blob/main/docs/compilers/Deterministic%20Inputs.md
        "DOTNET_MULTILEVEL_LOOKUP": "0",
    }

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

    return dotnet.new_library(
        dotnet = dotnet,
        name = name,
        deps = deps,
        result = result,
        ref_result = ref_result,
        pdb = pdb,
        data = data,
        output_groups = [OutputGroupInfo(targets = [propsfile])] if propsfile else [],
    )
