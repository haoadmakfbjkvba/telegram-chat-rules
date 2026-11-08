load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GroupRulesEditorScreen",
    module_name = "GroupRulesEditorScreen",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/PresentationDataUtils",
        "//submodules/AccountContext",
        "//submodules/ComponentFlow",
        "//submodules/Components/ViewControllerComponent",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/TelegramUI/Components/ButtonComponent",
        "//submodules/TelegramUI/Components/GroupRules",
    ],
    visibility = [
        "//visibility:public",
    ],
)
