load("@io_bazel_rules_dotnet//dotnet/private:rules/binary.bzl", "core_binary_no_server")

core_binary_no_server(
  name = "markup",
  out = "Markup.dll",
  srcs = glob(["**/*.cs"], exclude = ["**/obj/**", "**/bin/**"]),
  deps = [
    "@nuget//microsoft.netcore.app.ref",
    "@rules_dotnet_nuget_packages//microsoft.codeanalysis.csharp",
    "@core_sdk//:PresentationBuildTasks",
  ],
  visibility = ["//visibility:public"]
)
