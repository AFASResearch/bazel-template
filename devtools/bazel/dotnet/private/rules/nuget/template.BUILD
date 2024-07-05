load("@rules_dotnet//dotnet:defs.bzl", "import_library")

package(default_visibility = ["//visibility:public"])

import_library(
    name = "{VERSION}",
    analyzers = ["@{PREFIX}.{NAME_LOWER}.v{VERSION}//:analyzers"],
    data = ["@{PREFIX}.{NAME_LOWER}.v{VERSION}//:data", "@{PREFIX}.{NAME_LOWER}.v{VERSION}//:content_files"],
    library_name = "{NAME}",
    libs = ["@{PREFIX}.{NAME_LOWER}.v{VERSION}//:libs"],
    native = ["@{PREFIX}.{NAME_LOWER}.v{VERSION}//:native"],
    refs = ["@{PREFIX}.{NAME_LOWER}.v{VERSION}//:refs"],
    sha512 = "{SHA_512}",
    targeting_pack_overrides = "@{PREFIX}.{NAME_LOWER}.v{VERSION}//:overrides",
    version = "{VERSION}",
    deps = {DEPS},
)
