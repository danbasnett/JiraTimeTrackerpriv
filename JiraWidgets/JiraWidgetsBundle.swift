import WidgetKit
import SwiftUI

@main
struct JiraWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JiraTimerWidget()
        JiraTasksWidget()
        #if os(iOS)
        JiraTimerLiveActivity()
        #endif
    }
}
