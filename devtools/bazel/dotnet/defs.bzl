"""Public API surface is re-exported here.

Users should not load files under "/dotnet"
"""

load(
    "@rules_dotnet//dotnet/private/rules/nuget:imports.bzl",
    _import_dll = "import_dll",
    _import_library = "import_library",
)

import_library = _import_library
import_dll = _import_dll
