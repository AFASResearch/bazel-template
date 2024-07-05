load("@io_bazel_rules_dotnet//dotnet/private:rules/binary.bzl", "core_library_no_server")

core_library_no_server(
  name = "ManifestLoader",
  out = "ManifestLoader.dll",
  srcs = glob(["**/*.cs"], exclude = ["**/obj/**", "**/bin/**"]),
  deps = [
    "@nuget//microsoft.netcore.app.ref",
  ],
  visibility = ["//visibility:public"]
)
