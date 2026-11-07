import SwiftUI
import WidgetKit

@main
struct AdalmonWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AllBatteriesWidget()
        MacBatteryWidget()
        SystemWidget()
        MobileQuotaWidget()
    }
}
