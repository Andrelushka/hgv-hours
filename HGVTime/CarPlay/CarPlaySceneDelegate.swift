import CarPlay
import SwiftData
import UIKit

/// HGV Hours on the car's screen: your hours, activity buttons, and the next turn while navigating.
/// Uses the CarPlay "driving task" templates (no map). Needs Apple's CarPlay permission on the app to appear in a car;
/// it can be tried in Xcode's CarPlay Simulator.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var timer: Timer?
    private let hoursTemplate = CPInformationTemplate(title: "Hours", layout: .twoColumn, items: [], actions: [])
    private let routeTemplate = CPInformationTemplate(title: "Route", layout: .leading, items: [], actions: [])
    private lazy var activityTemplate = CPGridTemplate(title: "Activity", gridButtons: activityButtons())

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect controller: CPInterfaceController) {
        interfaceController = controller
        hoursTemplate.tabTitle = "Hours"
        hoursTemplate.tabImage = UIImage(systemName: "gauge.with.dots.needle.67percent")
        activityTemplate.tabTitle = "Activity"
        activityTemplate.tabImage = UIImage(systemName: "steeringwheel")
        routeTemplate.tabTitle = "Route"
        routeTemplate.tabImage = UIImage(systemName: "location.north.line.fill")
        let tabs = CPTabBarTemplate(templates: [hoursTemplate, activityTemplate, routeTemplate])
        controller.setRootTemplate(tabs, animated: false, completion: nil)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController controller: CPInterfaceController) {
        timer?.invalidate()
        timer = nil
        interfaceController = nil
    }

    // MARK: Content

    private var context: ModelContext { StoreSetup.shared.mainContext }

    private func refresh() {
        let settings = SettingsStore().settings
        let now = Date.now
        let snaps = ActivityController.recentSnapshots(context: context, settings: settings, now: now)
        let status = RulesEngine.status(snaps, now: now, config: settings.ruleConfig)
        let open = ActivityController.openEntries(context: context).last
        let d = Dashboard.make(status: status, settings: settings, openEntry: open)

        var items = [CPInformationItem(title: "Now", detail: "\(d.statusTitle) since \(Fmt.time(d.since))")]
        if d.onShift {
            items += [
                CPInformationItem(title: "Driving till break", detail: Fmt.hm(d.driveLeft)),
                CPInformationItem(title: "Working till break", detail: Fmt.hm(d.workLeft)),
                CPInformationItem(title: "Driving left today", detail: "\(Fmt.hm(d.driveLeftToday)) of \(Fmt.hm(d.dailyDrivingLimit))"),
                CPInformationItem(title: "Next break", detail: d.breakBy.map { "\(Int(d.breakLength / 60)) min by \(Fmt.time($0))" } ?? "—"),
                CPInformationItem(title: "Start rest by", detail: d.restBy.map(Fmt.time) ?? "—"),
                CPInformationItem(title: "Worked this shift", detail: Fmt.hm(d.shiftWorking)),
            ]
        } else if d.hasData {
            items.append(CPInformationItem(title: "Resting", detail: Fmt.hm(d.restLength)))
            if let next = d.nextStart { items.append(CPInformationItem(title: "Can start from", detail: Fmt.dayTime(next))) }
        }
        items += [
            CPInformationItem(title: "Week driving", detail: "\(Fmt.hm(d.weeklyDriving)) of 56h"),
            CPInformationItem(title: "Week working", detail: "\(Fmt.hm(d.weeklyWorking)) of 60h"),
        ]
        hoursTemplate.items = items

        let nav = NavigationEngine.shared
        if nav.isRunning {
            routeTemplate.items = [
                CPInformationItem(title: nav.distanceToNextManeuver.map(NavigationEngine.distanceText) ?? "Next", detail: nav.nextInstruction),
                CPInformationItem(title: "Road", detail: nav.currentRoad.isEmpty ? "—" : nav.currentRoad),
                CPInformationItem(title: "Arrive", detail: "\(nav.eta.map(Fmt.time) ?? "—") · \(Fmt.hm(nav.remainingTime)) · \(NavigationEngine.distanceText(nav.remainingDistance))"),
                CPInformationItem(title: "To", detail: nav.destinationName),
            ]
        } else {
            routeTemplate.items = [CPInformationItem(title: "Not navigating", detail: "Start navigation from the map on your iPhone; the next turn shows here.")]
        }
        activityTemplate.updateGridButtons(activityButtons(current: open?.kind, onShift: d.onShift))
    }

    private func activityButtons(current: DutyKind? = nil, onShift: Bool = true) -> [CPGridButton] {
        var buttons: [CPGridButton] = []
        if onShift {
            for (kind, title) in [(DutyKind.drive, "Drive"), (.otherWork, "Other work"), (.availability, "POA"), (.rest, "Break")] {
                let mark = kind == current ? "● " : ""
                buttons.append(CPGridButton(titleVariants: [mark + title], image: UIImage(systemName: kind.symbol) ?? UIImage()) { [weak self] _ in
                    self?.switchTo(kind)
                })
            }
            buttons.append(CPGridButton(titleVariants: ["End shift"], image: UIImage(systemName: "stop.circle.fill") ?? UIImage()) { [weak self] _ in
                self?.confirmEndShift()
            })
        } else {
            buttons.append(CPGridButton(titleVariants: ["Start shift"], image: UIImage(systemName: "play.circle.fill") ?? UIImage()) { [weak self] _ in
                guard let self else { return }
                ActivityController.startShift(context: self.context, settings: SettingsStore().settings)
                self.refresh()
            })
        }
        return buttons
    }

    private func switchTo(_ kind: DutyKind) {
        let settings = SettingsStore().settings
        ActivityController.switchTo(kind, context: context, settings: settings)
        ActivityController.refreshSideEffects(context: context, settings: settings)
        refresh()
    }

    private func confirmEndShift() {
        let alert = CPAlertTemplate(titleVariants: ["End shift and start daily rest?"], actions: [
            CPAlertAction(title: "End shift", style: .destructive) { [weak self] _ in
                guard let self else { return }
                let settings = SettingsStore().settings
                ActivityController.endShift(.daily, context: self.context, settings: settings)
                ActivityController.refreshSideEffects(context: self.context, settings: settings)
                self.interfaceController?.dismissTemplate(animated: true, completion: nil)
                self.refresh()
            },
            CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
            },
        ])
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }
}
