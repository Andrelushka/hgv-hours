import Foundation

/// UK vehicle details from the DVLA Vehicle Enquiry Service (needs the driver's own free API key).
enum DVLALookup {
    struct VehicleInfo {
        var make = ""
        var colour = ""
        var fuelType = ""
        var year = 0
        var revenueWeightKg = 0
        var typeApproval = ""
        var taxStatus = ""
        var taxDueDate = ""
        var motStatus = ""
        var motExpiryDate = ""

        var summary: String {
            [colour.capitalized, year > 0 ? "\(year)" : "", typeApproval,
             taxStatus.isEmpty ? "" : "Tax: \(taxStatus)\(taxDueDate.isEmpty ? "" : " (due \(taxDueDate))")",
             motStatus.isEmpty ? "" : "MOT: \(motStatus)\(motExpiryDate.isEmpty ? "" : " (expires \(motExpiryDate))")"]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }

        var fuel: FuelType? {
            switch fuelType.uppercased() {
            case "DIESEL", "HEAVY OIL": .dieselAdBlue
            case "PETROL": .petrol
            case "ELECTRICITY": .electric
            case let f where f.contains("HYBRID"): .hybrid
            case let f where f.contains("GAS"): .lng
            default: nil
            }
        }
    }

    enum Failure: LocalizedError {
        case noKey, notFound, rejected, other(Int)
        var errorDescription: String? {
            switch self {
            case .noKey: "Add your DVLA key in Jobs ⚙︎ → Registration & postcode lookup."
            case .notFound: "The DVLA has no vehicle with that registration."
            case .rejected: "The DVLA key was rejected."
            case .other(let code): "DVLA lookup failed (\(code))."
            }
        }
    }

    static func lookup(_ registration: String) async throws -> VehicleInfo {
        guard let key = DVLAKey.load(), !key.isEmpty else { throw Failure.noKey }
        var req = URLRequest(url: URL(string: "https://driver-vehicle-licensing.api.gov.uk/vehicle-enquiry/v1/vehicles")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["registrationNumber": normalisedReg(registration)])
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 404: throw Failure.notFound
        case 401, 403: throw Failure.rejected
        default: throw Failure.other(code)
        }
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var v = VehicleInfo()
        v.make = j["make"] as? String ?? ""
        v.colour = j["colour"] as? String ?? ""
        v.fuelType = j["fuelType"] as? String ?? ""
        v.year = j["yearOfManufacture"] as? Int ?? 0
        v.revenueWeightKg = j["revenueWeight"] as? Int ?? 0
        v.typeApproval = j["typeApproval"] as? String ?? ""
        v.taxStatus = j["taxStatus"] as? String ?? ""
        v.taxDueDate = j["taxDueDate"] as? String ?? ""
        v.motStatus = j["motStatus"] as? String ?? ""
        v.motExpiryDate = j["motExpiryDate"] as? String ?? ""
        return v
    }
}
