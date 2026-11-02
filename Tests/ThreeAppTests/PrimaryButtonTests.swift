import SwiftUI
import Testing
@testable import ThreeApp

/// Which label a prominent button gets was measured on the rendered glass (docs/menu-bar-design.md): white failed on
/// every category, and a dark label failed on idle grey. Category colours are editable, so dark ones keep white too.
struct PrimaryButtonTests {
    @Test func everyCategoryColourTakesADarkLabelWhileIdleAndDarkColoursKeepWhite() {
        for hex in ["#F2766B", "#6E9BF2", "#E5A84B", "#4FBF8B", "#A58AF0", "#5CC6D0", "#E57BB5", "#B8A27A"] {
            #expect(Color(hex: hex).isLight, "\(hex)")
        }
        #expect(!Theme.idle.isLight)
        #expect(!Color(hex: "#23305E").isLight)
    }
}
