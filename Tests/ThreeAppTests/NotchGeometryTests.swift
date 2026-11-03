import Foundation
import Testing
@testable import ThreeApp

struct NotchGeometryTests {
    private func screen(id: UInt32 = 1, builtIn: Bool = true, origin: CGPoint = .zero,
                        safeTop: CGFloat = 32) -> NotchScreen {
        NotchScreen(id: id, name: "Display \(id)", isBuiltIn: builtIn,
                    frame: CGRect(origin: origin, size: CGSize(width: 1512, height: 982)),
                    visibleFrame: CGRect(x: origin.x, y: origin.y + 64, width: 1512, height: 886),
                    safeTop: safeTop,
                    auxiliaryLeft: CGRect(x: origin.x, y: origin.y + 950, width: 650, height: 32),
                    auxiliaryRight: CGRect(x: origin.x + 862, y: origin.y + 950, width: 650, height: 32))
    }

    @Test func panelIsCenteredBelowCameraAndInsideVisibleSafeArea() throws {
        let display = screen()
        let placement = try #require(NotchGeometry.placement(screens: [display]))
        #expect(placement.frame == CGRect(x: 576, y: 798, width: 360, height: 144))
        #expect(display.visibleFrame.contains(placement.frame))
        #expect(!placement.frame.intersects(display.auxiliaryLeft))
        #expect(!placement.frame.intersects(display.auxiliaryRight))
        #expect(placement.frame.maxY < display.frame.maxY - display.safeTop)
    }

    @Test func negativeScreenOriginsPreserveGlobalPlacement() throws {
        for origin in [CGPoint(x: -2000, y: -1000), CGPoint(x: 1512, y: -982), CGPoint(x: -1512, y: 982)] {
            let display = screen(origin: origin)
            let frame = try #require(NotchGeometry.placement(screens: [display])).frame
            #expect(frame == CGRect(x: origin.x + 576, y: origin.y + 798, width: 360, height: 144))
            #expect(display.visibleFrame.contains(frame))
        }
    }

    @Test func publicGeometryAdaptsToDifferentCameraAndMenuBarDimensions() throws {
        let display = NotchScreen(id: 5, name: "Different geometry", isBuiltIn: true,
                                 frame: CGRect(x: -100, y: 50, width: 1800, height: 1100),
                                 visibleFrame: CGRect(x: -100, y: 80, width: 1800, height: 1010), safeTop: 48,
                                 auxiliaryLeft: CGRect(x: -100, y: 1102, width: 750, height: 48),
                                 auxiliaryRight: CGRect(x: 950, y: 1102, width: 750, height: 48))
        let frame = try #require(NotchGeometry.placement(screens: [display])).frame
        #expect(frame == CGRect(x: 620, y: 938, width: 360, height: 144))
        #expect(display.visibleFrame.contains(frame))
        #expect(frame.maxY < 1102)
    }

    @Test func supportedBuiltInWinsOverExternalAndDisconnectFallsBack() throws {
        let external = screen(id: 2, builtIn: false, origin: CGPoint(x: -1512, y: 0))
        let builtIn = screen()
        #expect(NotchGeometry.placement(screens: [external, builtIn])?.screenID == 1)
        #expect(NotchGeometry.placement(screens: [external])?.screenID == 2)
        let ordinaryExternal = screen(id: 3, builtIn: false, safeTop: 0)
        #expect(NotchGeometry.placement(screens: [ordinaryExternal, builtIn])?.screenID == 1)
        #expect(NotchGeometry.placement(screens: [ordinaryExternal]) == nil)
        #expect(NotchGeometry.placement(screens: []) == nil)
    }

    @Test func partialOrUnsafeGeometryNeverDrawsAFakeNotch() {
        let base = screen()
        let invalid: [(CGRect, CGFloat, CGRect, CGRect)] = [
            (base.visibleFrame, 0, base.auxiliaryLeft, base.auxiliaryRight),
            (base.visibleFrame, 32, .zero, .zero),
            (base.visibleFrame, 32, base.auxiliaryRight, base.auxiliaryLeft),
            (base.visibleFrame, 32, CGRect(x: 0, y: 900, width: 650, height: 32), base.auxiliaryRight),
            (base.visibleFrame, .nan, base.auxiliaryLeft, base.auxiliaryRight),
            (CGRect(x: 0, y: 0, width: 350, height: 950), 32, base.auxiliaryLeft, base.auxiliaryRight),
            (CGRect(x: 0, y: 0, width: 1512, height: 150), 32, base.auxiliaryLeft, base.auxiliaryRight),
            (CGRect(x: -1, y: 0, width: 1512, height: 950), 32, base.auxiliaryLeft, base.auxiliaryRight),
        ]
        for (visible, top, left, right) in invalid {
            let display = NotchScreen(id: 1, name: "Invalid", isBuiltIn: true, frame: base.frame,
                                      visibleFrame: visible, safeTop: top, auxiliaryLeft: left, auxiliaryRight: right)
            #expect(NotchGeometry.placement(screens: [display]) == nil)
        }
    }
}
