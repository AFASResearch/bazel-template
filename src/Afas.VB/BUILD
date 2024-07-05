load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "vb_binary")

vb_binary(
  name = "Afas.VB",
  out = "Afas.VB.dll",
  srcs = glob(["**/*.vb"], exclude = ["**/obj/**", "**/bin/**"]),
  deps = [
    "@nuget//microsoft.netcore.app.ref",
  ],
  dotnet_context_data = "//:afas_context_data",
  visibility = ["//visibility:public"]
)