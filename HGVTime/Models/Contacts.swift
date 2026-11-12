import Foundation

/// A phone number with a label ("Transport office", "Gatehouse"…).
struct PhoneContact: Codable, Hashable, Identifiable {
    var id = UUID()
    var label = ""
    var number = ""

    init(label: String = "", number: String = "") {
        self.label = label
        self.number = number
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        number = (try? c.decode(String.self, forKey: .number)) ?? ""
    }

    /// tel: link (digits and a leading +), nil if there's no number.
    var callURL: URL? { Self.callURL(number) }

    static func callURL(_ number: String) -> URL? {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

/// A company or agency client you work for: name, site location and phone numbers.
struct CompanyProfile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var address = ""
    var postcode = ""
    var latitude: Double?
    var longitude: Double?
    var phones: [PhoneContact] = []
    var email = ""
    var notes = ""
    /// Always show on Today (otherwise only when it's today's job company).
    var showOnToday = false

    init(name: String = "") { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        address = (try? c.decode(String.self, forKey: .address)) ?? ""
        postcode = (try? c.decode(String.self, forKey: .postcode)) ?? ""
        latitude = try? c.decode(Double.self, forKey: .latitude)
        longitude = try? c.decode(Double.self, forKey: .longitude)
        phones = (try? c.decode([PhoneContact].self, forKey: .phones)) ?? []
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        showOnToday = (try? c.decode(Bool.self, forKey: .showOnToday)) ?? false
    }

    var fullAddress: String { [address, postcode].filter { !$0.isEmpty }.joined(separator: ", ") }

    /// Same company as a job's company text (ignoring case and spaces).
    func matches(_ company: String) -> Bool {
        let a = name.trimmingCharacters(in: .whitespaces), b = company.trimmingCharacters(in: .whitespaces)
        return !a.isEmpty && a.caseInsensitiveCompare(b) == .orderedSame
    }
}

/// Emergency and road-incident numbers.
enum EmergencyNumbers {
    struct Entry: Hashable {
        var title: String
        var number: String
        var detail: String
        var symbol: String
        var urgent = false
    }

    static var uk: [Entry] {
        [Entry(title: String(localized: "Emergency — police, fire, ambulance, coastguard"), number: "999",
               detail: String(localized: "Life in danger, crime in progress, fire, serious crash."), symbol: "staroflife.fill", urgent: true),
         Entry(title: String(localized: "Emergency (works across Europe)"), number: "112",
               detail: String(localized: "Same as 999 in the UK; the emergency number in every EU country."), symbol: "phone.fill", urgent: true),
         Entry(title: String(localized: "Bridge strike or railway problem — Network Rail"), number: "03457 11 41 41",
               detail: String(localized: "Hit a railway bridge or a problem at a level crossing. Use the number on the bridge sign if there is one, and call 999 if anyone is hurt or the road or line is blocked."),
               symbol: "tram.fill"),
         Entry(title: String(localized: "Police — non-emergency"), number: "101",
               detail: String(localized: "Report a crime or incident that isn't an emergency (e.g. load theft found later)."), symbol: "shield.fill"),
         Entry(title: String(localized: "NHS — urgent medical help"), number: "111",
               detail: String(localized: "Medical advice when it's not life-threatening."), symbol: "cross.case.fill"),
         Entry(title: String(localized: "National Highways (England)"), number: "0300 123 5000",
               detail: String(localized: "Incidents, debris or hazards on motorways and major A roads in England."), symbol: "road.lanes"),
         Entry(title: String(localized: "Traffic Scotland"), number: "0800 028 1414",
               detail: String(localized: "Trunk road incidents in Scotland."), symbol: "road.lanes"),
         Entry(title: String(localized: "Traffic Wales"), number: "0300 123 1213",
               detail: String(localized: "Trunk road incidents in Wales."), symbol: "road.lanes"),
         Entry(title: String(localized: "Gas emergency"), number: "0800 111 999",
               detail: String(localized: "Smell of gas or a gas leak (Great Britain)."), symbol: "flame.fill"),
         Entry(title: String(localized: "Crimestoppers (anonymous)"), number: "0800 555 111",
               detail: String(localized: "Tell them about crime anonymously."), symbol: "person.fill.questionmark")]
    }

    static var abroad: [Entry] {
        [Entry(title: String(localized: "Europe — any EU country"), number: "112", detail: String(localized: "Police, fire and ambulance."), symbol: "globe.europe.africa.fill", urgent: true),
         Entry(title: String(localized: "Ireland"), number: "112", detail: String(localized: "112 or 999."), symbol: "globe.europe.africa.fill", urgent: true),
         Entry(title: String(localized: "USA and Canada"), number: "911", detail: String(localized: "Police, fire and ambulance."), symbol: "globe.americas.fill", urgent: true),
         Entry(title: String(localized: "Australia"), number: "000", detail: String(localized: "Police, fire and ambulance (112 works from mobiles)."), symbol: "globe.asia.australia.fill", urgent: true),
         Entry(title: String(localized: "New Zealand"), number: "111", detail: String(localized: "Police, fire and ambulance."), symbol: "globe.asia.australia.fill", urgent: true)]
    }
}
