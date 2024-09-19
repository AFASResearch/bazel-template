load("@io_bazel_rules_dotnet//dotnet/private:rules/binary.bzl", "core_binary_no_server")

core_binary_no_server(
    name = "simpleresgen",
    out = "simpleresgen.dll",
    srcs = glob(["**/*.cs"]),
    dotnet_context_data = "@io_bazel_rules_dotnet//:core_context_data",
    unsafe = True,
    visibility = ["//visibility:public"],
    deps = [
        "@rules_dotnet_nuget_packages//microsoft.netcore.app.ref",
        "@rules_dotnet_nuget_packages//system.resources.extensions",
    ],
)
