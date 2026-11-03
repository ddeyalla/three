import Foundation
import Testing
@testable import ThreeApp

/// The hover intent is pure; these tests are its clock.
struct NotchHoverIntentTests {
    private let open = NotchHoverIntent.expandDelay
    private let close = NotchHoverIntent.collapseDelay

    @Test func delaysAreShortEnoughToFeelDirect() {
        #expect((0.25...0.3).contains(open))
        #expect((0.35...0.45).contains(close))
    }

    @Test func passingOverTheNotchNeverOpensIt() {
        var intent = NotchHoverIntent()
        intent.pointer(inside: true, buttonDown: false, now: 10)
        #expect(!intent.isExpanded)
        #expect(intent.deadline == 10 + open)
        intent.pointer(inside: true, buttonDown: false, now: 10 + open - 0.01)
        #expect(!intent.isExpanded)
        intent.pointer(inside: false, buttonDown: false, now: 10 + open - 0.005)
        #expect(intent.phase == .collapsed)
        #expect(intent.deadline == nil)
        // A late wake after leaving does nothing.
        intent.pointer(inside: false, buttonDown: false, now: 10 + open)
        #expect(!intent.isExpanded)
    }

    @Test func restingOpensAtTheDeadlineAndMovingInsideDoesNotRestartTheDwell() {
        var intent = NotchHoverIntent()
        intent.pointer(inside: true, buttonDown: false, now: 0)
        intent.pointer(inside: true, buttonDown: false, now: 0.1)
        #expect(intent.deadline == open)
        intent.pointer(inside: true, buttonDown: false, now: open)
        #expect(intent.isExpanded)
        #expect(intent.deadline == nil)
    }

    @Test func reEnteringWithinTheCollapseDelayStaysOpen() {
        var intent = NotchHoverIntent()
        intent.click(inside: true)
        intent.pointer(inside: false, buttonDown: false, now: 5)
        #expect(intent.isExpanded)
        #expect(intent.deadline == 5 + close)
        intent.pointer(inside: true, buttonDown: false, now: 5 + close - 0.01)
        #expect(intent.phase == .expanded)
        #expect(intent.deadline == nil)
        // Leaving again restarts the full collapse delay.
        intent.pointer(inside: false, buttonDown: false, now: 6)
        intent.pointer(inside: false, buttonDown: false, now: 6 + close - 0.01)
        #expect(intent.isExpanded)
        intent.pointer(inside: false, buttonDown: false, now: 6 + close)
        #expect(intent.phase == .collapsed)
    }

    @Test func aHeldButtonNeverStartsOrFinishesOpening() {
        var intent = NotchHoverIntent()
        intent.pointer(inside: true, buttonDown: true, now: 0)
        #expect(intent.phase == .collapsed)
        intent.pointer(inside: true, buttonDown: false, now: 1)
        #expect(intent.deadline == 1 + open)
        // Pressing during the dwell (starting a drag across the menu bar) cancels it.
        intent.pointer(inside: true, buttonDown: true, now: 1 + open)
        #expect(intent.phase == .collapsed)
        // Releasing on the notch starts a fresh dwell.
        intent.pointer(inside: true, buttonDown: false, now: 3)
        intent.pointer(inside: true, buttonDown: false, now: 3 + open)
        #expect(intent.isExpanded)
        // Already open: a held button (pressing a control) does not close it.
        intent.pointer(inside: true, buttonDown: true, now: 4)
        #expect(intent.phase == .expanded)
    }

    @Test func clicksActImmediately() {
        var intent = NotchHoverIntent()
        intent.pointer(inside: true, buttonDown: false, now: 0)
        intent.click(inside: true)
        #expect(intent.phase == .expanded)
        intent.click(inside: false)
        #expect(intent.phase == .collapsed)
        intent.click(inside: true)
        intent.pointer(inside: false, buttonDown: false, now: 1)
        intent.click(inside: false)
        #expect(intent.phase == .collapsed)
        #expect(intent.deadline == nil)
    }

    @Test func pinnedStaysOpenUntilThePointerVisitsOrAClickElsewhere() {
        var intent = NotchHoverIntent()
        intent.pin()
        for time in stride(from: 0.0, through: 5, by: 0.5) {
            intent.pointer(inside: false, buttonDown: false, now: time)
            #expect(intent.phase == .expanded)
        }
        intent.pointer(inside: true, buttonDown: false, now: 6)
        #expect(!intent.pinned)
        intent.pointer(inside: false, buttonDown: false, now: 7)
        intent.pointer(inside: false, buttonDown: false, now: 7 + close)
        #expect(intent.phase == .collapsed)

        intent.pin()
        intent.click(inside: false)
        #expect(intent.phase == .collapsed)
        #expect(!intent.pinned)

        intent.pin()
        intent.reset()
        #expect(intent == NotchHoverIntent())
    }
}
