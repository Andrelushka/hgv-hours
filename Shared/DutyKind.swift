import SwiftUI

/// The four tachograph activity modes.
enum DutyKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case drive
    case otherWork
    case availability
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: String(localized: "Driving")
        case .otherWork: String(localized: "Other work")
        case .availability: String(localized: "Availability (POA)")
        case .rest: String(localized: "Break / rest")
        }
    }

    var shortTitle: String {
        switch self {
        case .drive: String(localized: "Drive")
        case .otherWork: String(localized: "Work")
        case .availability: String(localized: "POA")
        case .rest: String(localized: "Rest")
        }
    }

    var symbol: String {
        switch self {
        case .drive: "steeringwheel"
        case .otherWork: "hammer.fill"
        case .availability: "hourglass"
        case .rest: "bed.double.fill"
        }
    }

    var color: Color {
        switch self {
        case .drive: .blue
        case .otherWork: .orange
        case .availability: .purple
        case .rest: .green
        }
    }
}
