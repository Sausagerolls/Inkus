import Foundation
import WidgetKit

/// Pokes the WidgetCenter so the widget refreshes after the main app generates
/// or refreshes today's prompt.
enum WidgetReloadCoordinator {
    /// Kind constant must match the `kind` declared by `DailyPromptWidget`
    /// in the widget extension target.
    static let promptWidgetKind = "DailyPromptWidget"

    static func reloadPromptWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: promptWidgetKind)
    }
}
