import AppKit

/// Length that pushes every item left of a divider off the screen.
let COLLAPSED_DIVIDER_LENGTH: CGFloat = 10_000

/// Nonzero compact width keeps divider windows registered and positions distinct.
let EXPANDED_DIVIDER_LENGTH: CGFloat = 1

/// Bundle id of the process that hosts every menu bar item on macOS 26.
let CONTROL_CENTER_BUNDLE_ID = "com.apple.controlcenter"

/// Retains the original bundle ID so permissions and saved layouts survive the rename.
let OWN_BUNDLE_ID = "com.local.hider"

/// Legacy autosave names keep the existing divider and toggle positions.
enum OwnItemName {
    static let toggle = "HiderToggle"
    static let hiddenDivider = "HiderHiddenDivider"
    static let alwaysHiddenDivider = "HiderAlwaysHiddenDivider"
}

/// Where an icon lives relative to the two dividers.
enum BarSection: String, CaseIterable, Identifiable, Codable {
    case shown
    case hidden
    case alwaysHidden

    var id: String { rawValue }

    /// Section heading shown in the layout window.
    var title: String {
        switch self {
        case .shown: return "Shown Items"
        case .hidden: return "Hidden Items"
        case .alwaysHidden: return "Always Hidden"
        }
    }

    /// SF Symbol shown next to the heading.
    var symbolName: String {
        switch self {
        case .shown: return "eyeglasses"
        case .hidden: return "eyeglasses.slash"
        case .alwaysHidden: return "eye.slash.circle.fill"
        }
    }
}
