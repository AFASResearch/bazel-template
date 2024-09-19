load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)

def _map_only_sourcegen(a):
    # sourcegenerator or sourcegeneration
    # ImportGenerator.dll
    # RegularExpressions.Generator.dll
    return a.path if a.path.endswith(".dll") and (a.path.endswith("Generator.dll") or a.path.find(".SourceGenerat") >= 0 or a.path.find(".sourcegenerat") >= 0 or a.path.find("/analyzers/") == -1) else None

def xaml(dotnet, subdir, all_srcs, transitive, transitive_analyzers, transitive_refs, env, name, format_ref_with_overrides):    
    def _format_ref_with_overrides_non_ref(assembly):
        return [p.replace('.ref.dll', '.dll') for p in format_ref_with_overrides(assembly) if p]

    xamls = dotnet._ctx.files.xamls if hasattr(dotnet._ctx.files, "xamls") else None
    xaml_resources = dotnet._ctx.files.xaml_resources if hasattr(dotnet._ctx.files, "xaml_resources") else None
    
    #if dotnet._ctx.label.name == "Afas.Profit.Controls":
    #    fail(dotnet._ctx.files.xamls)

    if not xamls and not xaml_resources:
        return (None, None)

    markup = dotnet._ctx.executable.markup

    g_dir = None
    if xamls:
        g_dir = dotnet._ctx.actions.declare_directory(subdir + "g")

        xaml_args = dotnet.actions.args()
        xaml_args.use_param_file("@%s", use_always = True)
        xaml_args.set_param_file_format("multiline")
        xaml_args.add(g_dir.path)
        xaml_args.add_all(all_srcs, format_each = '/s:"%s"')
        xaml_args.add_all(xamls, format_each = '/x:"%s"')
        xaml_args.add_all(transitive, allow_closure = True, map_each = _format_ref_with_overrides_non_ref, format_each = '/r:"%s"')
        xaml_args.add_all(transitive_analyzers, map_each = _map_only_sourcegen, format_each = "/a:\"%s\"")
        xaml_args.add_all(dotnet._ctx.files.data, format_each = "/c:\"%s\"")

        dotnet.actions.run(
            inputs = depset(direct = xamls, transitive = [all_srcs, transitive_refs]),
            env = env,
            outputs = [g_dir],
            executable = markup,
            arguments = [xaml_args],
            mnemonic = "CoreCompile",
            # execution_requirements = { "supports-multiplex-workers": "1", "no-cache": "1" },
            tools = [markup],
            progress_message = (
                "Generating XAML code behinds " + dotnet.label.package
            )
        )
    
    g_resources = dotnet._ctx.actions.declare_file(subdir + name + ".g.resources")
    
    resource_args = dotnet.actions.args()
    resource_args.use_param_file("@%s", use_always = True)
    resource_args.set_param_file_format("multiline")        
    if g_dir:
        def _only_baml(p):
            return (p.path + "," + paths.relativize(p.path, g_dir.path)) if p.path.endswith(".baml") else None
        resource_args.add_all([g_dir], allow_closure = True, map_each = _only_baml)
    def _format_xaml_resource(file):
        return file.path + "," + paths.relativize(file.path, dotnet.label.package)
    resource_args.add_all(xaml_resources, allow_closure = True, map_each = _format_xaml_resource)
    resource_args.add(g_resources)

    resolve = dotnet._ctx.resolve_tools(tools = [dotnet._ctx.attr.simpleresgen])
    dotnet.actions.run(
        inputs = ([g_dir] if g_dir else []) + xaml_resources + resolve[0].to_list(),
        tools = dotnet._ctx.attr.simpleresgen.files,
        outputs = [g_resources],
        executable = dotnet._ctx.attr.simpleresgen.files_to_run.executable,
        arguments = [resource_args],
        env = {"RUNFILES_MANIFEST_FILE": dotnet._ctx.attr.simpleresgen.files_to_run.runfiles_manifest.path},
        mnemonic = "CoreResxCompile",
        input_manifests = resolve[1],
        progress_message = (
            "Compiling resources " + dotnet.label.package + ":" + dotnet.label.name
        ),
    )

    return (g_dir, g_resources)
