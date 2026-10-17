import CoreAudio

/// Snapshots of the CoreAudio device list.
package enum CoreAudioHardware {
    /// Every device with at least one output channel and a UID (FR-1).
    package static func outputDevices() -> [AudioDevice] {
        CoreAudioProperty.objectIDs(CoreAudioProperty.system, kAudioHardwarePropertyDevices).compactMap(device(for:))
    }

    package static func device(for id: AudioObjectID) -> AudioDevice? {
        let channels = CoreAudioProperty.outputChannelCount(id)
        guard channels > 0, let uid = CoreAudioProperty.string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let transport = CoreAudioProperty.value(id, kAudioDevicePropertyTransportType, as: UInt32.self) ?? 0
        let alive = CoreAudioProperty.value(id, kAudioDevicePropertyDeviceIsAlive, as: UInt32.self) ?? 0
        return AudioDevice(
            uid: uid,
            objectID: id,
            name: CoreAudioProperty.string(id, kAudioObjectPropertyName) ?? uid,
            transport: Transport(coreAudioTransportType: transport),
            outputChannels: channels,
            nominalSampleRate: CoreAudioProperty.value(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
                ?? 0,
            isAlive: alive != 0
        )
    }
}
