workspace(name = "vb")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//devtools/bazel:workspace_config.bzl", "workspace_config_repo")
workspace_config_repo(name = "workspace_config")

http_archive(
     name = "bazel_dotnet",
     urls = ["https://github.com/AFASResearch/bazel-dotnet/releases/download/v0.5.3/v0.5.3.zip"],
     sha256 = "a77d77f312b817a139c0cc0744cc9d8f13adcf8fb90c621ee9138a9a2e00202b",
     build_file_content = r"""
exports_files(["Afas.BazelDotnet.exe", "Afas.BazelDotnet.dll"])
"""
)

##########
# DOTNET #
##########

local_repository(
     name = "io_bazel_rules_dotnet",
     path = "devtools/bazel/rules_dotnet",
)

load("@io_bazel_rules_dotnet//dotnet:sdk.bzl", "core_register_sdk")
core_register_sdk(
    name = "core_sdk",
    version = "8.0.302",
    urls = [
        "https://download.visualstudio.microsoft.com/download/pr/5af098e1-e433-4fda-84af-3f54fd27c108/6bd1c6e48e64e64871957289023ca590/dotnet-sdk-8.0.302-win-x64.zip",
    ],
    integrity = "sha512-kitg7Bcw1qT8N7nXaWRtF4KhzwKThGy04ZkaYcq0iS9ceSqI30ceZbgt9RLW88g0HM5lDVJg0Ptk48a2IO/lxA==")

new_local_repository(
     name = "rules_dotnet",
     path = "devtools/bazel",
     build_file_content = "",
)

load(
    "@rules_dotnet//dotnet:repositories.bzl",
#     "dotnet_register_toolchains",
    "rules_dotnet_dependencies",
)
rules_dotnet_dependencies()

load("@rules_dotnet//dotnet:rules_dotnet_nuget_packages.bzl", "rules_dotnet_nuget_packages")
rules_dotnet_nuget_packages()

#########
# NuGet #
#########

load(":nuget-lock.bzl", "packages")
load("@rules_dotnet//dotnet/private/rules/nuget:nuget_repo.bzl", "nuget_repo")

nuget_repo(
     name = "nuget",
     packages = packages,
)
