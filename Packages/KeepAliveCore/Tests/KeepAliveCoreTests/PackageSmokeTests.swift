import KeepAliveCore
import Testing

@Test("NFR-9: logger subsystem equals the release bundle ID")
func loggerSubsystemMatchesBundleID() {
    #expect(KeepAliveCore.defaultSubsystem == "io.github.ovixdev.purrlo")
}
