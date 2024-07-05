# Bazel Sample Project

This solution contains two sample projects for our Bazel .NET setup. One for C# and one for VB.NET.

To build this project run:
```
bazel build src/...
```

# Bazel structure
We currently depend on two separate rules_dotnet implementations.

The upstream [bazel/rules_dotnet](https://github.com/bazelbuild/rules_dotnet) is used for NuGet dependency management and located in this repo at ./devtools/bazel/dotnet.

Our own [AFASResearch/rules_dotnet](https://github.com/AFASResearch/rules_dotnet) is used for the optimized compilation features and located in this repo at ./devtools/bazel/rules_dotnet.

A third project called [BazelDotnet](https://github.com/AFASResearch/bazel-dotnet) exists which contains some precompiled C# projects to solve the following three tasks:
1. NuGet resolution.
2. App.exe shim creation
3. BUILD file generation.

My objective for this solution is to get rid the pre-compile requirement and merge the tools into rules_dotnet. For NuGet resolution this has already been done which now is located at /devtools/bazel/nuget.

# NuGet
NuGet dependency resolution uses a ./Directory.Packages.props file to specify dependencies and a custom lockfile format such as ./nuget-lock.bzl that contains the transitive closure of nupkgs. Unfortunately we cannot use the existing NuGet central package management lockfile format since the hashes that it tracks differ from the nupkg file hash. See [this issue](https://github.com/bazelbuild/rules_dotnet/issues/444).

To update a lock file you can invoke the following command:
```
bazel run devtools/bazel/nuget -- repository $pwd/nuget.config $pwd/Directory.Packages.props $pwd/nuget-lock.bzl
```

# Compilation
The current state of the Bazel rules is in a make-it-work state. There are various unnecessary indirections that make it awkward for first-time readers. Ideally we slowly migrate our optimizations to upstream rules_dotnet. I am however a bit hesitant to do so since the upstream rules_dotnet is quite verbose whereas I prefer a very minimal solution to make it maintainable and understandable.

The main compilation [rules](https://bazel.build/extending/rules) are defined in [binary.bzl](.\devtools\bazel\rules_dotnet\dotnet\private\rules\binary.bzl).
These rules are  loaded in BUILD files and create Bazel [targets](https://bazel.build/concepts/build-ref#targets).
Internally the rules invoke the emit_assembly_core function from [assembly.bzl](.\devtools\bazel\rules_dotnet\dotnet\private\actions\assembly.bzl). Previously this was the only place where compiler flags were set. For the VB poc I however also added some language specific flags logic in binary.bzl.

## Persistent worker
One of the main optimizations we made to rules_dotnet is using a [Bazel Persistent Worker](https://bazel.build/remote/persistent). This is invoked instead of csc.dll in assembly.bzl. The server itself is implemented at .\devtools\bazel\rules_dotnet\tools\server and wraps Roslyns VBCSCompiler.dll and its [BuildProtocol](.\devtools\bazel\rules_dotnet\tools\server\BuildProtocol.cs).

Other optimizations include the use of (less volatile) [reference assememblies](https://learn.microsoft.com/en-us/dotnet/standard/assembly/reference-assemblies) when possible and Bazel's unused_inputs_list feature to prune the dependency graph after a Roslyn compilation.

# Less Copies
Another major improvement over MSBUILD and upstream rules_dotnet is that we prevent dll copies as much as possible. To achieve this we rely on Bazel's runfiles_manifest instead of copies/symlinks. At runtime dotnet executables load their dependencies trough this manifest using a custom AssemblyLoader. This loader is implemented at .\devtools\bazel\rules_dotnet\tools\loader.

# BUILD file generation
There is a BUILD file generator implemented in BazelDotnet which parsers csproj files and generates their BUILD files. Bazel also has a bigger BUILD file generation solution called [Gazelle](https://github.com/bazelbuild/bazel-gazelle). Since we plan to get rid of BazelDotnet I however think we can just replace the logic with a simple PowerShell script.

# IDE Support
Ide support is bootstrapped via .\Directory.Build.targets and implemented in .\devtools\bazel\Bazel.targets. One downside to this sapproach is that the IDE will build each project individually. This causes many (simulantious) Bazel invocations which causes a lot of overhead. As a solution to this we currently deploy a ReSharper/Rider plugin that catches all Build invocations and propagates them bundled to bazel. This plugin can be found here: https://dev.azure.com/afassoftware/Research/_git/resharper-bazel-plugin. Ideally there is an easier solution to this.

# BzlMod
Bazel has revamped its dependency logic with the [BzlMod project](https://bazel.build/external/overview#bzlmod). This is a major change that replaces the WORKSPACE file for a more flexible solution that supports transitive dependencies. It will be quite some work to migrate. See the link for more info.
