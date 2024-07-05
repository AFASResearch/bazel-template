load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def _dependencies():
    for name, config in {
        "bazel_skylib": {
            "sha256": "1c531376ac7e5a180e0237938a2536de0c54d93f5c278634818e0efc952dd56c",
            "urls": [
                "https://github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
                "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.0.3/bazel-skylib-1.0.3.tar.gz",
            ],
        },
    }.items():
        # if not name in native.existing_rules():
            http_archive(
                name = name,
                **config
            )

def _json_string_value(json, key):
    i = json.index(key)
    j = i + len(key) + 1 # include a "
    j = json.find(":", j) + 1
    s = json.find("\"", j) + 1
    e = json.find("\"", s)
    return json[s:e]

def _core_download_sdk_impl(ctx):
    ctx.template(
        "BUILD.bazel",
        Label("@io_bazel_rules_dotnet//dotnet/private:BUILD.sdk.bazel"),
        executable = False,
        substitutions = {
            "{name}": ctx.attr.name,
        }
    )

    ctx.download_and_extract(
        url = ctx.attr.urls,
        integrity = ctx.attr.integrity,
        output = ctx.path("."),
    )

    ctx.symlink("sdk/" + ctx.attr.version, "sdk/current")

    config = ctx.read("sdk/current/dotnet.runtimeconfig.json")

    ctx.file("version.bzl", r"""runtime_version = "{runtime_version}"
framework_version = "{framework_version}"
tfm = "{tfm}"
""".format(
    runtime_version = ctx.attr.version,
    framework_version = _json_string_value(config, "version"),
    tfm = _json_string_value(config, "tfm")))

    ctx.file("pathmap.bzl", "execroot_pathmap = {pathmap}".format(
      pathmap = repr(str(ctx.path(ctx.attr.workspace).dirname.dirname))))

core_download_sdk = repository_rule(
    _core_download_sdk_impl,
    attrs = {
        "urls": attr.string_list(),
        "integrity": attr.string(),
        "version": attr.string(),
        "workspace": attr.label(default = "@//:.gitattributes"),
    },
)

# Currently very simplified
def core_register_sdk(
    name = "core_sdk",
    version = "8.0.302",
    urls = [
        "https://download.visualstudio.microsoft.com/download/pr/5af098e1-e433-4fda-84af-3f54fd27c108/6bd1c6e48e64e64871957289023ca590/dotnet-sdk-8.0.302-win-x64.zip",
    ],
    integrity = "sha512-kitg7Bcw1qT8N7nXaWRtF4KhzwKThGy04ZkaYcq0iS9ceSqI30ceZbgt9RLW88g0HM5lDVJg0Ptk48a2IO/lxA==",
):
    _dependencies()

    core_download_sdk(
        name = name,
        version = version,
        urls = urls,
        integrity = integrity,
    )

    native.register_toolchains(
        "@{}//:{}".format(name, name),
    )
