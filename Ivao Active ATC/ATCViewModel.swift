import SwiftUI
import Foundation
import Combine
import MapKit
import CoreLocation

class ATCViewModel: ObservableObject {
    @Published var atcs: [Atc] = []
    @Published var pilots: [Pilot] = []
    @Published var countries: [RootCountry] = []
    @Published var polygonData: [WelcomeElement] = []
    @Published var pilotCounts: [String: (inbound: Int, outbound: Int, inRegion: Int)] = [:]
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    func updatePilotCounts(pilots: [Pilot]) {
        var counts: [String: (inbound: Int, outbound: Int, inRegion: Int)] = [:]
        
        for atc in atcs {
            let inRegionCount = countPilotsInRegion(for: atc)
            counts[atc.callsign] = (inbound: 0, outbound: 0, inRegion: inRegionCount)
        }
        
        for pilot in pilots {
            let departure = pilot.flightPlan?.departureId?.prefix(4)
            let arrival = pilot.flightPlan?.arrivalId?.prefix(4)
            
            
            for atc in atcs {
                let atcPrefix = atc.callsign.prefix(4)
                
                if atcPrefix == departure {
                    counts[atc.callsign, default: (0, 0, 0)].outbound += 1
                }
                if atcPrefix == arrival {
                    counts[atc.callsign, default: (0, 0, 0)].inbound += 1
                }
            }
        }
        DispatchQueue.main.async {
            self.pilotCounts = counts
        }
    }
    
    func countryName(fromCode code: String) -> String {
        if code.starts(with: "K") {
            return "us"
        }  else if code.starts(with: "Y") {
            return "au"
        }
        let x = countries.first { $0.Code == code }?.CCode?.lowercased() ?? "default"
        return x
    }
    
    func getCountryName(fromCode code: String) -> String {
        if code.starts(with: "K") {
            return "United States"
        }  else if code.starts(with: "Y") {
            return "au"
        }
        return countries.first { $0.Code == code }?.Country ?? "default"
    }
    
    func loadCountriesAsync() async {
        await MainActor.run {
            loadCountries()
        }
    }
    
    func fetchATCsAsync() async {
        guard let url = URL(string: "https://api.ivao.aero/v2/tracker/whazzup") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let root = try JSONDecoder().decode(Root.self, from: data)
            await MainActor.run {
                if !root.clients.atcs.isEmpty {
                    self.atcs = root.clients.atcs
                        .filter { $0.lastTrack != nil }
                        .sorted { $0.callsign < $1.callsign }
                    self.pilots = root.clients.pilots
                    self.updatePilotCounts(pilots: root.clients.pilots)
                    self.errorMessage = nil
                }
            }
        } catch let decodingError as DecodingError {
            let detail = decodingErrorDetail(decodingError)
            #if DEBUG
            print("Error fetching ATCs: \(detail)")
            #endif
            await MainActor.run { self.errorMessage = "ATC data error: \(detail)" }
        } catch {
            #if DEBUG
            print("Error fetching ATCs: \(error)")
            #endif
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
    
    func fetchPolygonDataAsync() async {
        guard let url = URL(string: "https://api.ivao.aero/v2/tracker/now/atc/summary") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let elements = try JSONDecoder().decode([WelcomeElement].self, from: data)
            await MainActor.run {
                if !elements.isEmpty {
                    self.polygonData = elements
                }
            }
        } catch let decodingError as DecodingError {
            let detail = decodingErrorDetail(decodingError)
            #if DEBUG
            print("Error fetching polygon data: \(detail)")
            #endif
            await MainActor.run { self.errorMessage = "Polygon data error: \(detail)" }
        } catch {
            #if DEBUG
            print("Error fetching polygon data: \(error)")
            #endif
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
    
    private func decodingErrorDetail(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Null value for \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
    
    func getStationName(fromCode callsign: String) -> String {
        if let element = polygonData.first(where: { $0.callsign == callsign }) {
            switch element.atcSession.position {
            case .ctr, .fss:
                return element.subcenter?.atcCallsign ?? "Unknown CTR/FSS"
            default:
                return element.atcPosition?.atcCallsign ?? "Unknown Station"
            }
        }
        return "Station Not Found"
    }
    
    func loadCountries() {
        if let loadedCountries = loadJson(filename: "countries") {
            countries = loadedCountries.map { country in
                var modifiedCountry = country
                if country.Code.starts(with: "K") {
                    modifiedCountry.Country = "United States"
                    modifiedCountry.CCode = "US"
                }
                return modifiedCountry
            }
        } else {
            #if DEBUG
            print("Failed to load countries from JSON")
            #endif
        }
    }
    
    func fetchPolygonData() {
        Task {
            await fetchPolygonDataAsync()
        }
    }
    
    func loadJson(filename fileName: String) -> [RootCountry]? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            #if DEBUG
            print("JSON file not found.")
            #endif
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let jsonData = try decoder.decode([RootCountry].self, from: data)
            return jsonData
        } catch {
            #if DEBUG
            print("Error decoding JSON: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    func fetchATCs() {
        Task {
            await fetchATCsAsync()
        }
    }
}

// MARK: - Point-in-Polygon & Region Counting

extension ATCViewModel {
    func isPointInPolygon(point: CLLocationCoordinate2D, polygon: [RegionMap]) -> Bool {
        var isInside = false
        let nvert = polygon.count
        var j = nvert - 1
        
        for i in 0..<nvert {
            if ((polygon[i].lat > point.latitude) != (polygon[j].lat > point.latitude)) &&
                (point.longitude < (polygon[j].lng - polygon[i].lng) * (point.latitude - polygon[i].lat) / (polygon[j].lat - polygon[i].lat) + polygon[i].lng) {
                isInside = !isInside
            }
            j = i
        }
        
        return isInside
    }
    
    func countPilotsInRegion(for atc: Atc) -> Int {
        guard let element = polygonData.first(where: { $0.callsign == atc.callsign }),
              (element.atcSession.position == .ctr || element.atcSession.position == .fss) else {
            return 0
        }
        
        let regionMap: [RegionMap]
        if let positionRegionMap = element.atcPosition?.regionMap {
            regionMap = positionRegionMap
        } else if let subcenterRegionMap = element.subcenter?.regionMap {
            regionMap = subcenterRegionMap
        } else {
            return 0
        }
        
        return pilots.filter { pilot in
            guard let lastTrack = pilot.lastTrack else { return false }
            let pilotCoordinate = CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude)
            return isPointInPolygon(point: pilotCoordinate, polygon: regionMap)
        }.count
    }
}
