@testable import KeepAliveCore
import Testing

@Suite("Diagnostics report")
struct DiagnosticsReportTests {
    // The required test name is the whole sentence.
    // swiftlint:disable:next line_length
    @Test("NFR-9: a report with a Bluetooth UID and a home path contains the speaker name and not the address or the path")
    func redactsAddressAndHome() {
        let address = "E8-4C-4A-8A-9A-39"
        let report = DiagnosticsReport.make(
            marketingVersion: "0.1.0",
            build: "1",
            osVersion: "26.0",
            state: "streaming",
            keepAlive: true,
            signal: "tone",
            preventIdleSleep: true,
            disconnectBeforeSleep: true,
            reconnectAfterUnlock: true,
            targetName: "Kitchen Speaker",
            targetUID: "\(address):output",
            transitions: [],
            logExtract: "saw \(address):output under /Users/ada/Library",
            homeDirectory: "/Users/ada"
        )
        #expect(report.contains("Kitchen Speaker"))
        #expect(report.contains("bt…9A-39"))
        #expect(!report.contains(address))
        #expect(!report.contains("/Users/ada"))
    }
}
