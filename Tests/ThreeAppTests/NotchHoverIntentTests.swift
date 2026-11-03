import Foundation
import Testing
@testable import ThreeApp

/// The hover intent is pure; these tests are its clock. They assert only what the user sees,
/// `isExpanded`, at given times, sampling the way the controller does (on pointer events, and
/// again whenever a pending transition is due).
struct NotchHoverIntentTests {
    /// A pointer that stays put from `from` to `to`, sampled every 10ms like a pending wake would.
    private func rest(_ intent: inout NotchHoverIntent, inside: Bool, buttonDown: Bool = false,
                      from: TimeInterval, to: TimeInterval) {
        for time in stride(from: from, through: to, by: 0.01) {
            intent.pointer(inside: inside, buttonDown: buttonDown, now: time)
        }
    }

    @Test func passingOverTheNotchNeverOpensIt() {
        var intent = NotchHoverIntent()
        rest(&intent, inside: true, from: 10, to: 10.2)
        #expect(!intent.isExpanded)
        rest(&intent, inside: false, from: 10.21, to: 12)
        #expect(!intent.isExpanded)
    }

    @Test func restingOpensItWithinAThirdOfASecond() {
        var intent = NotchHoverIntent()
        rest(&intent, inside: true, from: 0, to: 0.24)
        #expect(!intent.isExpanded)
        rest(&intent, inside: true, from: 0.25, to: 0.3)
        #expect(intent.isExpanded)
    }

    @Test func leavingClosesItAfterADelayAndReturningKeepsItOpen() {
        var intent = NotchHoverIntent()
        intent.click(inside: true)
        rest(&intent, inside: false, from: 5, to: 5.3)
        #expect(intent.isExpanded)
        rest(&intent, inside: true, from: 5.31, to: 5.4)
        #expect(intent.isExpanded)
        // Leaving again restarts the full delay.
        rest(&intent, inside: false, from: 6, to: 6.3)
        #expect(intent.isExpanded)
        rest(&intent, inside: false, from: 6.31, to: 6.5)
        #expect(!intent.isExpanded)
    }

    @Test func aHeldButtonNeverOpensItAndReleasingStartsTheDwell() {
        var intent = NotchHoverIntent()
        rest(&intent, inside: true, buttonDown: true, from: 0, to: 2)
        #expect(!intent.isExpanded)
        // Pressing partway through the dwell (starting a drag) cancels it.
        rest(&intent, inside: true, from: 3, to: 3.15)
        rest(&intent, inside: true, buttonDown: true, from: 3.16, to: 4)
        #expect(!intent.isExpanded)
        rest(&intent, inside: true, from: 5, to: 5.3)
        #expect(intent.isExpanded)
        // Already open: holding a button (pressing a control) does not close it.
        rest(&intent, inside: true, buttonDown: true, from: 6, to: 8)
        #expect(intent.isExpanded)
    }

    @Test func clicksActImmediately() {
        var intent = NotchHoverIntent()
        intent.pointer(inside: true, buttonDown: false, now: 0)
        intent.click(inside: true)
        #expect(intent.isExpanded)
        intent.click(inside: false)
        #expect(!intent.isExpanded)
        // A click elsewhere while a close is pending closes at once, and nothing reopens later.
        intent.click(inside: true)
        intent.pointer(inside: false, buttonDown: false, now: 1)
        intent.click(inside: false)
        #expect(!intent.isExpanded)
        rest(&intent, inside: false, from: 1, to: 3)
        #expect(!intent.isExpanded)
    }

    @Test func pinnedStaysOpenWhileThePointerIsAwayThenTimesOut() {
        var intent = NotchHoverIntent()
        intent.pin(now: 0)
        #expect(intent.deadline == NotchHoverIntent.pinTimeout)
        rest(&intent, inside: false, from: 0, to: 5.9)
        #expect(intent.isExpanded)
        rest(&intent, inside: false, from: 6, to: 6.1)
        #expect(!intent.isExpanded)
    }

    @Test func keyboardUseKeepsAPinOpen() {
        var intent = NotchHoverIntent()
        intent.pin(now: 0)
        intent.interacted(now: 5)
        rest(&intent, inside: false, from: 5, to: 10.9)
        #expect(intent.isExpanded)
        rest(&intent, inside: false, from: 11, to: 11.1)
        #expect(!intent.isExpanded)
    }

    @Test func visitingAPinnedSurfaceHandsItBackToHover() {
        var intent = NotchHoverIntent()
        intent.pin(now: 0)
        rest(&intent, inside: true, from: 1, to: 2)
        rest(&intent, inside: false, from: 2.01, to: 2.3)
        #expect(intent.isExpanded)
        rest(&intent, inside: false, from: 2.31, to: 2.5)
        #expect(!intent.isExpanded)
    }

    @Test func aPinWithoutTimeoutEndsOnlyByVisitClickOrReset() {
        var intent = NotchHoverIntent()
        intent.pin(now: 0, timeout: nil)
        rest(&intent, inside: false, from: 0, to: 30)
        #expect(intent.isExpanded)
        intent.click(inside: false)
        #expect(!intent.isExpanded)

        // Display sleep or a screen change resets, dropping the pin.
        intent.pin(now: 40, timeout: nil)
        intent.reset()
        #expect(!intent.isExpanded)
        rest(&intent, inside: false, from: 40, to: 41)
        #expect(!intent.isExpanded)
    }
}
