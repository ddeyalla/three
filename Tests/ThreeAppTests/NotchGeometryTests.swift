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

    /// Geometry read from a 14-inch MacBook Pro (Built-in Retina Display, 1512x982 points).
    private let macBookPro14 = NotchScreen(id: 1, name: "Built-in Retina Display", isBuiltIn: true,
                                           frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                           visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949), safeTop: 32,
                                           auxiliaryLeft: CGRect(x: 0, y: 950, width: 663.5, height: 32),
                                           auxiliaryRight: CGRect(x: 848.5, y: 950, width: 663.5, height: 32))

    @Test func surfaceHugsTheCameraHousingOnTheTopEdge() throws {
        let display = macBookPro14
        let placement = try #require(NotchGeometry.placement(screens: [display]))
        #expect(placement.layout == NotchLayout(notchWidth: 185, notchHeight: 32))
        // Panel: flush with the top edge, centred on the camera, sized for the expanded state.
        #expect(placement.frame == CGRect(x: 550, y: 854, width: 412, height: 128))
        #expect(placement.frame.maxY == display.frame.maxY)
        #expect(placement.frame.midX == 756)
        // Collapsed: exactly the notch height, the notch plus one wing either side.
        #expect(placement.collapsedRect == CGRect(x: 599.5, y: 950, width: 313, height: 32))
        let notch = CGRect(x: display.auxiliaryLeft.maxX, y: 950, width: 185, height: 32)
        #expect(placement.collapsedRect.contains(notch))
        // Wings stay inside the menu-bar areas beside the camera.
        let leftWing = CGRect(x: placement.collapsedRect.minX, y: 950, width: NotchLayout.wingWidth, height: 32)
        let rightWing = CGRect(x: notch.maxX, y: 950, width: NotchLayout.wingWidth, height: 32)
        #expect(display.auxiliaryLeft.contains(leftWing))
        #expect(display.auxiliaryRight.contains(rightWing))
        #expect(placement.collapsedRect.width <= 2 * NotchLayout.wingWidth + 185)
        #expect(placement.expandedRect == placement.frame.insetBy(dx: NotchLayout.ear, dy: 0))
    }

    @Test func negativeScreenOriginsPreserveGlobalPlacement() throws {
        for origin in [CGPoint(x: -2000, y: -1000), CGPoint(x: 1512, y: -982), CGPoint(x: -1512, y: 982)] {
            let display = screen(origin: origin)
            let placement = try #require(NotchGeometry.placement(screens: [display]))
            #expect(placement.frame == CGRect(x: origin.x + 550, y: origin.y + 854, width: 412, height: 128))
            #expect(placement.collapsedRect == CGRect(x: origin.x + 586, y: origin.y + 950, width: 340, height: 32))
            #expect(display.frame.contains(placement.frame))
        }
    }

    @Test func publicGeometryAdaptsToDifferentCameraAndMenuBarDimensions() throws {
        let display = NotchScreen(id: 5, name: "Different geometry", isBuiltIn: true,
                                 frame: CGRect(x: -100, y: 50, width: 1800, height: 1100),
                                 visibleFrame: CGRect(x: -100, y: 80, width: 1800, height: 1010), safeTop: 48,
                                 auxiliaryLeft: CGRect(x: -100, y: 1102, width: 750, height: 48),
                                 auxiliaryRight: CGRect(x: 950, y: 1102, width: 750, height: 48))
        let placement = try #require(NotchGeometry.placement(screens: [display]))
        // A wide notch widens the expanded surface so it never gets narrower than collapsed.
        #expect(placement.layout.expandedSize == CGSize(width: 428, height: 144))
        #expect(placement.frame == CGRect(x: 580, y: 1006, width: 440, height: 144))
        #expect(placement.collapsedRect == CGRect(x: 586, y: 1102, width: 428, height: 48))
    }

    @Test func hoverExpandsFromTheNotchAndCollapsesOnlyAfterLeavingTheSurface() throws {
        let placement = try #require(NotchGeometry.placement(screens: [macBookPro14]))
        func wants(_ x: CGFloat, _ y: CGFloat, expanded: Bool) -> Bool {
            NotchGeometry.wantsExpanded(mouse: CGPoint(x: x, y: y), expanded: expanded, placement: placement)
        }
        // Collapsed: the camera, either wing, and the very top pixel row all expand.
        #expect(wants(756, 970, expanded: false))
        #expect(wants(610, 960, expanded: false))
        #expect(wants(900, 960, expanded: false))
        #expect(wants(756, 982, expanded: false))
        // Collapsed: menu-bar items beside the wings and the area under the notch do not.
        #expect(!wants(590, 970, expanded: false))
        #expect(!wants(920, 970, expanded: false))
        #expect(!wants(756, 900, expanded: false))
        // Expanded: moving down into the controls keeps it open; leaving the surface collapses.
        #expect(wants(756, 900, expanded: true))
        #expect(wants(560, 870, expanded: true))
        #expect(!wants(756, 840, expanded: true))
        #expect(!wants(500, 900, expanded: true))
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
            (base.visibleFrame, 32, CGRect(x: 0, y: 950, width: 650, height: 32),
             CGRect(x: 1460, y: 950, width: 52, height: 32)),
            (base.visibleFrame, 32, CGRect(x: 600, y: 950, width: 50, height: 32), base.auxiliaryRight),
            (CGRect(x: -1, y: 0, width: 1512, height: 950), 32, base.auxiliaryLeft, base.auxiliaryRight),
        ]
        for (visible, top, left, right) in invalid {
            let display = NotchScreen(id: 1, name: "Invalid", isBuiltIn: true, frame: base.frame,
                                      visibleFrame: visible, safeTop: top, auxiliaryLeft: left, auxiliaryRight: right)
            #expect(NotchGeometry.placement(screens: [display]) == nil)
        }
    }
}
