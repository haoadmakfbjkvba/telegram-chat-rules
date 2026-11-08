load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GroupRules",
    module_name = "GroupRules",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/ComponentFlow",
        "//submodules/PresentationDataUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)
