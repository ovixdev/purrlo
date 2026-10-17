import CoreAudio
import Testing

/// L2 tests need BlackHole; fail loudly instead of skipping when it is missing.
@Test("L2 prerequisite: BlackHole 2ch and 16ch are visible to CoreAudio")
func blackHoleIsInstalled() throws {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    try #require(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try #require(AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr)

    let uids: [String] = ids.compactMap { id in
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
    let hint = "BlackHole missing: run scripts/e2e/setup-ci.sh (or install it and restart coreaudiod)"
    #expect(uids.contains("BlackHole2ch_UID"), Comment(rawValue: hint))
    #expect(uids.contains("BlackHole16ch_UID"), Comment(rawValue: hint))
}
