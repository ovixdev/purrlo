import Foundation
@testable import KeepAliveCore
import KeepAliveTestSupport
import Testing

extension L2Hardware {
    @MainActor
    @Suite("DeviceMonitor against BlackHole")
    struct DeviceMonitorIntegrationTests {
        @Test("FR-1: lists BlackHole outputs with transport, channels and rate")
        func listsVirtualDevices() throws {
            let monitor = CoreAudioDeviceMonitor()
            monitor.start { _ in }
            defer { monitor.stop() }

            let twoChannel = try #require(monitor.devices.first { $0.uid == VirtualDevice.blackHole2chUID })
            #expect(twoChannel.transport == .virtual)
            #expect(twoChannel.outputChannels == 2)
            #expect(twoChannel.isAlive)
            #expect(twoChannel.nominalSampleRate > 0)
            let sixteen = try #require(monitor.devices.first { $0.uid == VirtualDevice.blackHole16chUID })
            #expect(sixteen.outputChannels == 16)
            #expect(monitor.devices.allSatisfy { $0.outputChannels > 0 })
        }

        @Test("FR-1, EC-7: a created device appears and a destroyed one disappears within 1 s")
        func appearsAndDisappears() async throws {
            let uid = "l2-speaker-\(UUID().uuidString)"
            let monitor = CoreAudioDeviceMonitor()
            var latest: [AudioDevice] = []
            monitor.start { latest = $0 }
            defer {
                monitor.stop()
                try? VirtualDevice.destroy(uid: uid)
            }

            try VirtualDevice.create(name: "L2 Speaker", uid: uid, on: VirtualDevice.blackHole2chUID)
            #expect(await waitUntil(timeout: .seconds(1)) { latest.contains { $0.uid == uid } })
            let created = try #require(latest.first { $0.uid == uid })
            #expect(created.name == "L2 Speaker")
            #expect(created.transport == .aggregate)
            #expect(monitor.devices == latest)

            try VirtualDevice.destroy(uid: uid)
            #expect(await waitUntil(timeout: .seconds(1)) { !latest.contains { $0.uid == uid } })
        }

        @Test("EC-6: a sample-rate change is reported, as one coalesced snapshot")
        func sampleRateChange() async throws {
            let uid = VirtualDevice.blackHole2chUID
            let original = try #require(VirtualDevice.nominalSampleRate(uid: uid))
            let other: Double = original == 44100 ? 48000 : 44100
            let monitor = CoreAudioDeviceMonitor()
            var deliveries: [[AudioDevice]] = []
            monitor.start { deliveries.append($0) }
            defer { monitor.stop() }
            // Let the initial listener snapshot settle before counting.
            try await Task.sleep(for: .milliseconds(300))
            deliveries.removeAll()

            try await withBlackHoleRate(other) {
                let rate = { deliveries.last?.first { $0.uid == uid }?.nominalSampleRate }
                #expect(await waitUntil(timeout: .seconds(1)) { rate() == other })
                try await Task.sleep(for: .milliseconds(300))
                #expect(deliveries.count == 1, "got \(deliveries.count) snapshots for one rate change")
            }
        }

        @Test("FR-3: stop() ends deliveries")
        func stopEndsDeliveries() async throws {
            let uid = "l2-stop-\(UUID().uuidString)"
            let monitor = CoreAudioDeviceMonitor()
            var deliveries = 0
            monitor.start { _ in deliveries += 1 }
            try await Task.sleep(for: .milliseconds(200))
            monitor.stop()
            let before = deliveries
            try VirtualDevice.create(name: "L2 Stop", uid: uid, on: VirtualDevice.blackHole2chUID)
            defer { try? VirtualDevice.destroy(uid: uid) }
            try await Task.sleep(for: .milliseconds(300))
            #expect(deliveries == before)
        }
    }
}
