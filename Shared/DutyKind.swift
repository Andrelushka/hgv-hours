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
        case .drive: "Driving"
        case .otherWork: "Other work"
        case .availability: "Availability (POA)"
        case .rest: "Break / rest"
        }
    }

    var shortTitle: String {
        switch self {
        case .drive: "Drive"
        case .otherWork: "Work"
        case .availability: "POA"
        case .rest: "Rest"
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
