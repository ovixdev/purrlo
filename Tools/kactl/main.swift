import Foundation
import KeepAliveTestSupport

/// `kactl`: drives and inspects a running E2E build of Purrlo (PRD §6, §8). Never shipped.
let usage = """
usage: kactl <command> [arguments]

app (over the E2E control socket):
  status                              current state as JSON
  devices                             output devices as the app sees them
  set-target <uid>                    choose the target speaker
  set <setting> <value>               keepAlive|preventIdleSleep|launchAtLogin true|false, signal tone|silence
  transitions                         ordered transition log since launch
  calls                               Bluetooth and helper calls recorded by --fake-* ports
  wait <state> [--timeout <s>]        poll until the app is in <state>; prints the seconds it took
  quit                                quit the app gracefully

virtual devices (CoreAudio):
  vdev create --name <name> --uid <uid> [--on <sub-device uid>]   aggregate on BlackHole 2ch by default
  vdev destroy --uid <uid>
  vdev rate --uid <uid>               print the nominal sample rate
  vdev set-rate --uid <uid> <rate>
  record --device <uid|name> --seconds <n> --out <file.wav>
  default-output [<uid>]              print, or set, the default output device
  device-running <uid>                1 if any process does IO on the device, else 0
"""

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("kactl: \(message)\n".utf8))
    exit(code)
}

/// `--name value` style options after the subcommand.
func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func required(_ name: String, in args: [String]) -> String {
    guard let value = option(name, in: args) else { fail("missing \(name)\n\(usage)", code: 64) }
    return value
}

// MARK: App control

/// Sends one request to the app and returns the raw JSON response line.
func send(_ cmd: String, _ args: [String] = []) throws -> Data {
    let path = ControlProtocol.socketURL().path
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw Failure(description: "socket() failed") }
    defer { close(socketFD) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in bytes.withUnsafeBytes { raw.copyMemory(from: $0) } }
    let connected = withUnsafePointer(to: &address) {
        $0
            .withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
    }
    guard connected == 0 else { throw Failure(description: "app not running (no socket at \(path))") }

    var request = try JSONEncoder().encode(ControlRequest(cmd: cmd, args: args))
    request.append(0x0A)
    _ = request.withUnsafeBytes { write(socketFD, $0.baseAddress, $0.count) }
    var response = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = read(socketFD, &buffer, buffer.count)
        if count <= 0 {
            break
        }
        response.append(buffer, count: count)
    }
    return response
}

/// Prints the response and exits non-zero when the app reported an error.
func forward(_ cmd: String, _ args: [String] = []) -> Never {
    do {
        let response = try send(cmd, args)
        FileHandle.standardOutput.write(response)
        let object = try JSONSerialization.jsonObject(with: response) as? [String: Any]
        exit(object?["ok"] as? Bool == true ? 0 : 1)
    } catch {
        fail("\(error)")
    }
}

func currentState() -> String? {
    guard let response = try? send("status"),
          let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
          let result = object["result"] as? [String: Any]
    else { return nil }
    return result["state"] as? String
}

func wait(for state: String, timeout: Double) -> Never {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if currentState() == state {
            print(String(format: "%.3f", Date().timeIntervalSince(start)))
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    fail("still \(currentState() ?? "unreachable") after \(timeout) s, expected \(state)")
}

// MARK: Devices

func resolveUID(_ nameOrUID: String) -> String {
    if VirtualDevice.deviceID(uid: nameOrUID) != nil {
        return nameOrUID
    }
    if nameOrUID == "BlackHole" || nameOrUID == "BlackHole 2ch" {
        return VirtualDevice.blackHole2chUID
    }
    if nameOrUID == "BlackHole 16ch" {
        return VirtualDevice.blackHole16chUID
    }
    fail("no device \(nameOrUID)")
}

func vdev(_ args: [String]) throws {
    switch args.first {
    case "create":
        let id = try VirtualDevice.create(
            name: required("--name", in: args),
            uid: required("--uid", in: args),
            on: option("--on", in: args) ?? VirtualDevice.blackHole2chUID
        )
        print(id)
    case "destroy":
        try VirtualDevice.destroy(uid: required("--uid", in: args))
    case "rate":
        let uid = resolveUID(required("--uid", in: args))
        guard let rate = VirtualDevice.nominalSampleRate(uid: uid)
        else { throw Failure(description: "no rate for \(uid)") }
        print(Int(rate))
    case "set-rate":
        guard let rate = args.last.flatMap(Double.init) else { fail("set-rate needs a rate", code: 64) }
        try VirtualDevice.setNominalSampleRate(rate, uid: resolveUID(required("--uid", in: args)))
    default:
        fail(usage, code: 64)
    }
}

func record(_ args: [String]) throws {
    let uid = resolveUID(required("--device", in: args))
    guard let seconds = Double(required("--seconds", in: args)) else { fail("--seconds must be a number", code: 64) }
    let recording = try Recorder.record(uid: uid, seconds: seconds)
    try Recorder.wavData(recording).write(to: URL(fileURLWithPath: required("--out", in: args)))
}

// MARK: Main

let arguments = Array(CommandLine.arguments.dropFirst())
let rest = Array(arguments.dropFirst())

do {
    switch arguments.first {
    case "status", "devices", "transitions", "calls", "quit":
        forward(arguments[0])
    case "set-target":
        guard rest.count == 1 else { fail("set-target <uid>", code: 64) }
        forward("set-target", rest)
    case "set":
        guard rest.count == 2 else { fail("set <setting> <value>", code: 64) }
        forward("set", rest)
    case "simulate":
        forward("simulate", rest)
    case "wait":
        guard let state = rest.first else { fail("wait <state> [--timeout <s>]", code: 64) }
        wait(for: state, timeout: option("--timeout", in: rest).flatMap(Double.init) ?? 5)
    case "vdev":
        try vdev(rest)
    case "record":
        try record(rest)
    case "default-output":
        if let uid = rest.first {
            try VirtualDevice.setDefaultOutput(uid: resolveUID(uid))
        } else {
            print(VirtualDevice.defaultOutputUID() ?? "none")
        }
    case "device-running":
        guard let uid = rest.first else { fail("device-running <uid>", code: 64) }
        print(VirtualDevice.isRunningSomewhere(uid: resolveUID(uid)) ? 1 : 0)
    case "version":
        print("kactl 0.1.0")
    case nil, "help", "--help", "-h":
        print(usage)
    default:
        fail("unknown command '\(arguments[0])'\n\(usage)", code: 64)
    }
} catch {
    fail("\(error)")
}
