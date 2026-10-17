import CoreAudio
import Dispatch

/// Output device list with presence, renames, sample-rate and AudioObjectID changes (FR-1, FR-3, EC-3, EC-6, EC-7).
@MainActor
public protocol DeviceMonitoring: AnyObject {
    var devices: [AudioDevice] { get }
    /// Delivers the full list on the main actor whenever it changes, until `stop()`.
    func start(onChange: @escaping @MainActor ([AudioDevice]) -> Void)
    func stop()
}

@MainActor
public final class CoreAudioDeviceMonitor: DeviceMonitoring {
    public private(set) var devices: [AudioDevice] = []
    private let listener: CoreAudioListener
    private var onChange: (@MainActor ([AudioDevice]) -> Void)?

    /// - Parameter coalescing: bursts of CoreAudio notifications inside this window produce one snapshot,
    ///   so one sample-rate change does not cause two engine restarts.
    public init(coalescing: DispatchTimeInterval = .milliseconds(50)) {
        listener = CoreAudioListener(coalescing: coalescing)
    }

    public func start(onChange: @escaping @MainActor ([AudioDevice]) -> Void) {
        self.onChange = onChange
        devices = CoreAudioHardware.outputDevices()
        listener.start { [weak self] snapshot in
            // DispatchQueue.main keeps snapshots in order, unlike separate Tasks.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.deliver(snapshot) }
            }
        }
    }

    public func stop() {
        listener.stop()
        onChange = nil
    }

    private func deliver(_ snapshot: [AudioDevice]) {
        guard let onChange, snapshot != devices else { return }
        devices = snapshot
        onChange(snapshot)
    }
}

/// All CoreAudio listeners on one private serial queue (PRD §6). Every stored property is confined to `queue`.
final class CoreAudioListener: @unchecked Sendable {
    private static let deviceSelectors: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal),
        (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
        (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
        (kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput),
    ]

    private let queue = DispatchQueue(label: "io.github.ovixdev.purrlo.coreaudio")
    private let coalescing: DispatchTimeInterval
    private var handler: (@Sendable ([AudioDevice]) -> Void)?
    private var systemBlock: AudioObjectPropertyListenerBlock?
    private var deviceBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var refreshPending = false

    init(coalescing: DispatchTimeInterval) {
        self.coalescing = coalescing
    }

    func start(handler: @escaping @Sendable ([AudioDevice]) -> Void) {
        queue.async { [self] in
            guard systemBlock == nil else { return }
            self.handler = handler
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
            var address = CoreAudioProperty.address(kAudioHardwarePropertyDevices)
            AudioObjectAddPropertyListenerBlock(CoreAudioProperty.system, &address, queue, block)
            systemBlock = block
            refresh()
        }
    }

    func stop() {
        queue.sync {
            if let systemBlock {
                var address = CoreAudioProperty.address(kAudioHardwarePropertyDevices)
                AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.system, &address, queue, systemBlock)
            }
            systemBlock = nil
            for id in Array(deviceBlocks.keys) {
                removeDeviceListeners(id)
            }
            handler = nil
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        queue.asyncAfter(deadline: .now() + coalescing) { [self] in
            refreshPending = false
            refresh()
        }
    }

    private func refresh() {
        guard let handler else { return }
        let snapshot = CoreAudioHardware.outputDevices()
        let current = Set(snapshot.map(\.objectID))
        for id in deviceBlocks.keys where !current.contains(id) {
            removeDeviceListeners(id)
        }
        for id in current where deviceBlocks[id] == nil {
            addDeviceListeners(id)
        }
        handler(snapshot)
    }

    private func addDeviceListeners(_ id: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
        for (selector, scope) in Self.deviceSelectors {
            var address = CoreAudioProperty.address(selector, scope: scope)
            AudioObjectAddPropertyListenerBlock(id, &address, queue, block)
        }
        deviceBlocks[id] = block
    }

    private func removeDeviceListeners(_ id: AudioObjectID) {
        guard let block = deviceBlocks.removeValue(forKey: id) else { return }
        for (selector, scope) in Self.deviceSelectors {
            var address = CoreAudioProperty.address(selector, scope: scope)
            AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
        }
    }
}
