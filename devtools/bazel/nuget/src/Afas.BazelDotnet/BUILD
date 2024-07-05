load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "core_binary")
resources = []


filegroup(
  name = "Afas.BazelDotnet__data",
  srcs = [],
  visibility = ["//visibility:public"]
)

core_binary(
  name = "Afas.BazelDotnet",
  out = "Afas.BazelDotnet.dll",
  srcs = glob(["**/*.cs"], exclude = ["**/obj/**", "**/bin/**"]),
  resources = resources,
  data = [":Afas.BazelDotnet__data"],
  deps = [
    "@nuget//microsoft.netcore.app.ref",
    "@nuget//mcmaster.extensions.commandlineutils",
    "@nuget//microsoft.net.hostmodel",
    "@nuget//nuget.commands",
    "@nuget//nuget.common",
    "@nuget//nuget.configuration",
    "@nuget//nuget.dependencyresolver.core",
    "@nuget//nuget.frameworks",
    "@nuget//nuget.packagemanagement",
    "@nuget//nuget.packaging.core",
    "@nuget//nuget.packaging",
    "@nuget//nuget.projectmodel",
    "@nuget//nuget.protocol",
    "@nuget//nuget.resolver",
    "@nuget//nuget.versioning"
  ],
  dotnet_context_data = "//:afas_context_data",
  visibility = ["//visibility:public"]
)