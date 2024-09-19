load("@bazel_skylib//lib:paths.bzl", "paths")
load("@io_bazel_rules_dotnet//dotnet/private:providers.bzl", "DotnetLibrary")

preferred_packages = {
    'microsoft.netcore.app.ref': 0,
    'microsoft.windowsdesktop.app.ref': 1,
    'microsoft.aspnetcore.app.ref': 2,
    'microsoft.windows.sdk.net.ref': 3,
}
def _should_be_dropped(assembly_version, other_assembly_version, package_name, other_package_name):
    if not other_assembly_version:
        return False
    
    if other_assembly_version > assembly_version:
        return True
    
    if other_assembly_version == assembly_version and preferred_packages[other_package_name.lower()] < preferred_packages[package_name.lower()]:
        return True
    return False

def conflict_resolution_closure(deps):
    overrides = { d[DotnetLibrary].name: d[DotnetLibrary].targeting_pack_overrides for d in deps if hasattr(d[DotnetLibrary], 'targeting_pack_overrides') and d[DotnetLibrary].targeting_pack_overrides }
    
    def _format_ref_with_overrides(target):
        provider = target[DotnetLibrary]

        # resolve conflicts between targeting packs
        if hasattr(provider, 'targeting_pack_overrides') and provider.targeting_pack_overrides:

            drops = { assembly_name: True 
                for (other_name, other) in overrides.items() if other_name != provider.name
                    for (assembly_name, assembly_version) in provider.targeting_pack_overrides.items() if _should_be_dropped(assembly_version, other.get(assembly_name, None), provider.name, other_name) }

            return [f.path for f in provider.refs if drops.get(paths.split_extension(paths.basename(f.path))[0].lower(), False) == False]

        # resolve conflicts between a nuget package and a targeting pack. We drop the nuget ref if the targeting pack has a >= major
        # TODO a winning nuget package is not yet supported due to technical reasons 
        if provider.version:
            version = [int(v) for v in provider.version.split("-", 2)[0].split(".", 3)]

            for o in overrides.values():
                override_version = o.get(provider.name.lower(), None)
                # only compare the major version. For referencing we prefer the targeting pack to win because the other way around is not (yet) supported
                if override_version and override_version[0] >= version[0]:
                    return []

        return [f.path for f in provider.refs]
    
    return _format_ref_with_overrides
