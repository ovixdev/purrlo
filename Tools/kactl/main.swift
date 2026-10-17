import Foundation

/// `kactl`: drives and inspects a running E2E build of Purrlo (PRD §6, §8). Never shipped.
let usage = """
usage: kactl <command> [arguments]

commands:
  version    print the kactl version
"""

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "version":
    print("kactl 0.1.0")
case nil, "help", "--help", "-h":
    print(usage)
default:
    FileHandle.standardError.write(Data("kactl: unknown command '\(arguments[0])'\n\(usage)\n".utf8))
    exit(64)
}
