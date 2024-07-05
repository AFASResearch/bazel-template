load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "core_binary")

core_binary(
  name = "Afas.CS",
  out = "Afas.CS.dll",
  srcs = glob(["**/*.cs"], exclude = ["**/obj/**", "**/bin/**"]),
  deps = [
    "@nuget//microsoft.netcore.app.ref",
  ],
  dotnet_context_data = "//:afas_context_data",
  visibility = ["//visibility:public"]
)