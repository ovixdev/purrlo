#if !E2E_HOOKS
    import Foundation
    import IOBluetooth
    import KeepAliveCore
    import os

    /// The only IOBluetooth calls in the app. The E2E build does not compile this (FR-11, FR-12, §6).
    @MainActor
    final class BluetoothController: BluetoothControlling {
        private let logger: Logger
        private let timeout: Duration
        private var namedDevices: [String: IOBluetoothDevice] = [:]
        private var waiter: ConnectionWaiter?

        init(subsystem: String, timeout: Duration = .seconds(15)) {
            logger = Logger(subsystem: subsystem, category: "bluetooth")
            self.timeout = timeout
        }

        func controls(for devices: [AudioDevice]) -> [String: BluetoothControl] {
            let paired = pairedDevices()
            let names = paired.compactMap(\.name)
            var named: [String: IOBluetoothDevice] = [:]
            var result: [String: BluetoothControl] = [:]
            for device in devices {
                let control = classify(device, paired: paired, names: names)
                result[device.uid] = control
                if control == .byUniqueName, let match = paired.first(where: { $0.name == device.name }) {
                    named[device.uid] = match
                }
            }
            namedDevices = named
            return result
        }

        func disconnect(uid: String) {
            guard let device = resolve(uid) else {
                logger.info("closeConnection \(logUID(uid), privacy: .public) no paired device")
                return
            }
            let status = device.closeConnection()
            logger.info("closeConnection \(logUID(uid), privacy: .public) status \(status)")
        }

        func connect(uid: String) async -> Bool {
            guard let device = resolve(uid) else {
                logger.info("openConnection \(logUID(uid), privacy: .public) no paired device")
                return false
            }
            let waiter = ConnectionWaiter()
            self.waiter = waiter
            let gate = ResumeOnce()
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiter.onComplete = { [weak self] status in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.finish(
                                ok: status == kIOReturnSuccess, gate: gate, continuation: continuation, uid: uid,
                                status: status, timedOut: false
                            )
                        }
                    }
                }
                let immediate = device.openConnection(waiter)
                if immediate != kIOReturnSuccess {
                    let already = device.isConnected()
                    finish(
                        ok: already, gate: gate, continuation: continuation, uid: uid, status: immediate,
                        timedOut: false
                    )
                    return
                }
                let limit = timeout
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: limit)
                    guard let self else {
                        gate.perform { continuation.resume(returning: false) }
                        return
                    }
                    self.finish(
                        ok: false, gate: gate, continuation: continuation, uid: uid, status: 0, timedOut: true
                    )
                }
            }
        }

        private func classify(
            _ device: AudioDevice, paired: [IOBluetoothDevice], names: [String]
        ) -> BluetoothControl {
            if let address = BluetoothAddress(coreAudioUID: device.uid),
               IOBluetoothDevice(addressString: address.description) != nil
            {
                return .byAddress
            }
            guard device.transport.isBluetooth else { return .unavailable }
            return BluetoothMatch.matchName(device.name, pairedNames: names)
        }

        private func resolve(_ uid: String) -> IOBluetoothDevice? {
            if let address = BluetoothAddress(coreAudioUID: uid),
               let device = IOBluetoothDevice(addressString: address.description)
            {
                return device
            }
            return namedDevices[uid]
        }

        private func pairedDevices() -> [IOBluetoothDevice] {
            (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        }

        private func finish(
            ok: Bool,
            gate: ResumeOnce,
            continuation: CheckedContinuation<Bool, Never>,
            uid: String,
            status: IOReturn,
            timedOut: Bool
        ) {
            gate.perform {
                if timedOut {
                    logger.info("openConnection \(logUID(uid), privacy: .public) timed out")
                } else {
                    logger.info("openConnection \(logUID(uid), privacy: .public) status \(status)")
                }
                waiter = nil
                continuation.resume(returning: ok)
            }
        }
    }

    /// Retained until `connectionComplete:status:` or the timeout. IOBluetooth may call back off the main thread.
    private final class ConnectionWaiter: NSObject {
        var onComplete: (@Sendable (IOReturn) -> Void)?

        @objc(connectionComplete:status:)
        func connectionComplete(_: IOBluetoothDevice, status: IOReturn) {
            onComplete?(status)
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func perform(_ body: () -> Void) {
            lock.lock()
            let first = !fired
            fired = true
            lock.unlock()
            if first {
                body()
            }
        }
    }
#endif
