"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "get_highest_compatible_target_framework",
)
load("//dotnet/private/transitions:common.bzl", "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS", "RID_COMPATABILITY_TRANSITION_OUTPUTS")
load("//dotnet/private:rids.bzl", "RUNTIME_GRAPH")

def _impl(settings, attr):
    incoming_tfm = settings["@rules_dotnet//dotnet:target_framework"]

    if incoming_tfm not in FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS:
        fail("Error setting @rules_dotnet//dotnet:target_framework: invalid value '" + incoming_tfm + "'. Allowed values are " + str(FRAMEWORK_COMPATIBILITY.keys()))

    target_frameworks = "net8.0"
    if Label("@nuget//netstandard.library") in attr.deps:
        target_frameworks = "netstandard2.0"
    if Label("@nuget//microsoft.windows.sdk.net.ref") in attr.deps:
        target_frameworks = "net8.0-windows"
    if Label("@nuget//microsoft.netframework.referenceassemblies.net48") in attr.deps:
        target_frameworks = "net48"

    transitioned_tfm = get_highest_compatible_target_framework(incoming_tfm, target_frameworks)

    if transitioned_tfm == None:
        fail("Label {0} does not support the target framework: {1}".format(attr.name, incoming_tfm))

    runtime_identifier = settings["@rules_dotnet//dotnet:rid"]
    if hasattr(attr, "runtime_identifier"):
        runtime_identifier = attr.runtime_identifier

    return {
        "references": dicts.add({"@rules_dotnet//dotnet:target_framework": transitioned_tfm}, {"@rules_dotnet//dotnet:rid": runtime_identifier}, FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[transitioned_tfm], RID_COMPATABILITY_TRANSITION_OUTPUTS[runtime_identifier]),
        "propagate": dicts.add({"@rules_dotnet//dotnet:target_framework": incoming_tfm}, {"@rules_dotnet//dotnet:rid": runtime_identifier}, FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[incoming_tfm], RID_COMPATABILITY_TRANSITION_OUTPUTS[runtime_identifier]),
    }

def _netstandard_impl(settings, attr):
    transitioned_tfm = "netstandard2.0"
    return dicts.add({"@rules_dotnet//dotnet:target_framework": transitioned_tfm}, FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[transitioned_tfm])

tfm_outputs = ["@rules_dotnet//dotnet:target_framework"] + ["@rules_dotnet//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()]

rid_outputs = ["@rules_dotnet//dotnet:rid"] + ["@rules_dotnet//dotnet:rid_compatible_%s" % rid for rid in RUNTIME_GRAPH.keys()]

tfm_transition = transition(
    implementation = _impl,
    inputs = ["@rules_dotnet//dotnet:target_framework", "@rules_dotnet//dotnet:rid", "//command_line_option:cpu", "//command_line_option:platforms"],
    outputs = tfm_outputs + rid_outputs,
)

netstandard_transition = transition(
    implementation = _netstandard_impl,
    inputs = [],
    outputs = tfm_outputs,
)
