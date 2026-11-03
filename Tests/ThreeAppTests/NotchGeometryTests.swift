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
        #expect(placement.layout == NotchLayout(notchWidth: 185, notchHeight: 32, wingWidth: 44))
        // Panel: flush with the top edge, centred on the camera, sized for the expanded state.
        #expect(placement.frame == CGRect(x: 550, y: 854, width: 412, height: 128))
        #expect(placement.frame.maxY == display.frame.maxY)
        #expect(placement.frame.midX == 756)
        // Collapsed: exactly the notch height, the notch plus one 44pt wing either side.
        #expect(placement.collapsedRect == CGRect(x: 619.5, y: 950, width: 273, height: 32))
        let notch = CGRect(x: display.auxiliaryLeft.maxX, y: 950, width: 185, height: 32)
        #expect(placement.collapsedRect.contains(notch))
        // Wings stay inside the menu-bar areas beside the camera.
        let wing = placement.layout.wingWidth
        let leftWing = CGRect(x: placement.collapsedRect.minX, y: 950, width: wing, height: 32)
        let rightWing = CGRect(x: notch.maxX, y: 950, width: wing, height: 32)
        #expect(display.auxiliaryLeft.contains(leftWing))
        #expect(display.auxiliaryRight.contains(rightWing))
        #expect(placement.collapsedRect.width <= 2 * NotchLayout.maxWingWidth + 185)
        // The body hangs below the menu bar, centred on the camera.
        #expect(placement.bodyRect == CGRect(x: 556, y: 854, width: 400, height: 96))
    }

    /// Geometry read from this Mac at its current scaling (1800x1169 points, 220pt notch).
    @Test func surfaceStaysClearOfStatusItemsAtLargerScaling() throws {
        let display = NotchScreen(id: 1, name: "Built-in Retina Display", isBuiltIn: true,
                                  frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
                                  visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1131), safeTop: 38,
                                  auxiliaryLeft: CGRect(x: 0, y: 1131, width: 790, height: 38),
                                  auxiliaryRight: CGRect(x: 1010, y: 1131, width: 790, height: 38))
        let placement = try #require(NotchGeometry.placement(screens: [display]))
        #expect(placement.layout == NotchLayout(notchWidth: 220, notchHeight: 38, wingWidth: 44))
        #expect(placement.collapsedRect == CGRect(x: 746, y: 1131, width: 308, height: 38))
        #expect(placement.frame == CGRect(x: 694, y: 1035, width: 412, height: 134))
        // The right wing and its ear reach at most 50pt past the camera, whatever the state.
        #expect(placement.collapsedRect.maxX + NotchLayout.ear - display.auxiliaryRight.minX == 50)
    }

    @Test func wingsShrinkToKeepAMarginInsideNarrowMenuBarAreas() throws {
        let base = screen()
        let narrow = NotchScreen(id: 1, name: "Narrow", isBuiltIn: true, frame: base.frame,
                                 visibleFrame: base.visibleFrame, safeTop: 32,
                                 auxiliaryLeft: base.auxiliaryLeft,
                                 auxiliaryRight: CGRect(x: 1462, y: 950, width: 50, height: 32))
        let placement = try #require(NotchGeometry.placement(screens: [narrow]))
        #expect(placement.layout.wingWidth == 50 - NotchLayout.ear - NotchLayout.edgeMargin)
        #expect(placement.collapsedRect.maxX + NotchLayout.ear + NotchLayout.edgeMargin == narrow.frame.maxX)
        for side in [narrow.auxiliaryLeft, narrow.auxiliaryRight] {
            let reach = placement.layout.wingWidth + NotchLayout.ear + NotchLayout.edgeMargin
            #expect(reach <= side.width)
        }
    }

    /// Expanded, the surface grows down, never sideways across the menu-bar row.
    @Test func expandedSurfaceNeverWidensInTheMenuBarRow() throws {
        let displays = [macBookPro14, screen(), screen(origin: CGPoint(x: -1512, y: 982))]
        for display in displays {
            let placement = try #require(NotchGeometry.placement(screens: [display]))
            let neck = placement.collapsedRect.insetBy(dx: -Space.xs, dy: 0)
            for y in stride(from: display.frame.maxY - 1, through: display.frame.maxY - display.safeTop + 1, by: -1) {
                for x in stride(from: display.frame.minX, through: display.frame.maxX, by: 1) {
                    let point = CGPoint(x: x, y: y)
                    if NotchGeometry.contains(point, expanded: true, placement: placement) {
                        #expect(point.x >= neck.minX && point.x <= neck.maxX)
                    }
                }
            }
            #expect(placement.bodyRect.maxY == display.frame.maxY - display.safeTop)
        }
    }

    @Test func negativeScreenOriginsPreserveGlobalPlacement() throws {
        for origin in [CGPoint(x: -2000, y: -1000), CGPoint(x: 1512, y: -982), CGPoint(x: -1512, y: 982)] {
            let display = screen(origin: origin)
            let placement = try #require(NotchGeometry.placement(screens: [display]))
            #expect(placement.frame == CGRect(x: origin.x + 550, y: origin.y + 854, width: 412, height: 128))
            #expect(placement.collapsedRect == CGRect(x: origin.x + 606, y: origin.y + 950, width: 300, height: 32))
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
        #expect(placement.layout.expandedSize == CGSize(width: 400, height: 144))
        #expect(placement.frame == CGRect(x: 594, y: 1006, width: 412, height: 144))
        #expect(placement.collapsedRect == CGRect(x: 606, y: 1102, width: 388, height: 48))
    }

    @Test func hoverRegionIsTheNotchWhenCollapsedAndNeckPlusBodyWhenExpanded() throws {
        let placement = try #require(NotchGeometry.placement(screens: [macBookPro14]))
        func over(_ x: CGFloat, _ y: CGFloat, expanded: Bool) -> Bool {
            NotchGeometry.contains(CGPoint(x: x, y: y), expanded: expanded, placement: placement)
        }
        // Collapsed: the camera, either wing, and the very top pixel row count.
        #expect(over(756, 970, expanded: false))
        #expect(over(630, 960, expanded: false))
        #expect(over(880, 960, expanded: false))
        #expect(over(756, 982, expanded: false))
        // Collapsed: menu-bar items beside the wings and the area under the notch do not.
        #expect(!over(610, 970, expanded: false))
        #expect(!over(900, 970, expanded: false))
        #expect(!over(756, 900, expanded: false))
        // Expanded: moving down into the controls stays on the surface.
        #expect(over(756, 900, expanded: true))
        #expect(over(560, 870, expanded: true))
        #expect(over(895, 970, expanded: true))
        // Expanded: below the body, beside it, and status items in the menu-bar row are off it.
        #expect(!over(756, 840, expanded: true))
        #expect(!over(500, 900, expanded: true))
        #expect(!over(920, 970, expanded: true))
        #expect(!over(590, 970, expanded: true))
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
             CGRect(x: 1472, y: 950, width: 40, height: 32)),
            (base.visibleFrame, 32, CGRect(x: 610, y: 950, width: 40, height: 32), base.auxiliaryRight),
            (CGRect(x: -1, y: 0, width: 1512, height: 950), 32, base.auxiliaryLeft, base.auxiliaryRight),
        ]
        for (visible, top, left, right) in invalid {
            let display = NotchScreen(id: 1, name: "Invalid", isBuiltIn: true, frame: base.frame,
                                      visibleFrame: visible, safeTop: top, auxiliaryLeft: left, auxiliaryRight: right)
            #expect(NotchGeometry.placement(screens: [display]) == nil)
        }
    }

    /// The drawn shape, at every step of the animation, stays within the neck and its ears in the
    /// menu-bar row, and matches the collapsed and expanded sizes at the ends.
    @Test func drawnShapeGrowsDownWithoutCrossingIntoStatusItems() throws {
        let layout = try #require(NotchGeometry.placement(screens: [macBookPro14])).layout
        let panel = CGRect(origin: .zero, size: layout.panelSize)
        let neckHalf = layout.collapsedSize.width / 2 + NotchLayout.ear
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            let path = NotchShape(progress: progress, layout: layout).path(in: panel)
            let height = layout.notchHeight + NotchLayout.expandedBodyHeight * progress
            #expect(abs(path.boundingRect.maxY - height) < 0.01)
            for y in stride(from: 0.5, to: layout.notchHeight - 1, by: 1) {
                for x in [panel.midX - neckHalf - 1, panel.midX + neckHalf + 1] {
                    #expect(!path.contains(CGPoint(x: x, y: y)))
                }
            }
            #expect(path.contains(CGPoint(x: panel.midX, y: layout.notchHeight / 2)))
        }
        let collapsed = NotchShape(progress: 0, layout: layout).path(in: panel).boundingRect
        #expect(abs(collapsed.width - (layout.collapsedSize.width + NotchLayout.ear * 2)) < 0.01)
        let expanded = NotchShape(progress: 1, layout: layout).path(in: panel).boundingRect
        #expect(abs(expanded.width - layout.expandedSize.width) < 0.01)
        #expect(abs(expanded.height - layout.expandedSize.height) < 0.01)
    }
}
