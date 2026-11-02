import Testing
@testable import ThreeCore

@Test func bundleIDIsStable() {
    #expect(ThreeVersion.bundleID == "com.deyalla.three")
}
