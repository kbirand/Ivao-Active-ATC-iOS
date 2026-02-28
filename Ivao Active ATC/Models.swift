import SwiftUI
import UIKit
import Foundation
import Combine
import MapKit
import SQLite3
import CoreLocation


struct WelcomeElement: Codable, Identifiable {
    let id, userId: Int
    let callsign: String
    let connectionType: String?
    let atcSession: AtcSessionV2
    let atcPosition: AtcPosition?
    let subcenter: Subcenter?
}

struct AtcPosition: Codable {
    let airportId: String
    let atcCallsign: String
    let military: Bool
    let middleIdentifier: String?
    let position, composePosition: String
    let regionMap: [RegionMap]
    let regionMapPolygon: [[Double]]?
    let airport: Airport
    
    enum CodingKeys: String, CodingKey {
        case airportId
        case atcCallsign, military, middleIdentifier, position, composePosition, regionMap, regionMapPolygon, airport
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        airportId = try container.decode(String.self, forKey: .airportId)
        atcCallsign = try container.decode(String.self, forKey: .atcCallsign)
        if let boolValue = try? container.decode(Bool.self, forKey: .military) {
            military = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .military) {
            military = stringValue == "1" || stringValue.lowercased() == "true"
        } else {
            military = false
        }
        middleIdentifier = try container.decodeIfPresent(String.self, forKey: .middleIdentifier)
        position = try container.decode(String.self, forKey: .position)
        composePosition = try container.decode(String.self, forKey: .composePosition)
        regionMap = try container.decode([RegionMap].self, forKey: .regionMap)
        regionMapPolygon = try container.decodeIfPresent([[Double]].self, forKey: .regionMapPolygon)
        airport = try container.decode(Airport.self, forKey: .airport)
    }
}

struct Airport: Codable {
    let icao: String
    let iata: String?
    let name: String?
    let countryID: String?
    let city: String?
    let latitude, longitude: Double
    let military: Bool
    
    enum CodingKeys: String, CodingKey {
        case icao, iata, name
        case countryID = "countryId"
        case city, latitude, longitude, military
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        icao = try container.decode(String.self, forKey: .icao)
        iata = try container.decodeIfPresent(String.self, forKey: .iata)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        countryID = try container.decodeIfPresent(String.self, forKey: .countryID)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        if let boolValue = try? container.decode(Bool.self, forKey: .military) {
            military = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .military) {
            military = stringValue == "1" || stringValue.lowercased() == "true"
        } else {
            military = false
        }
    }
}

enum Position: String, Codable {
    case app = "APP"
    case ctr = "CTR"
    case del = "DEL"
    case gnd = "GND"
    case twr = "TWR"
    case fss = "FSS"
    case unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Position(rawValue: rawValue) ?? .unknown
    }
}

struct RegionMap: Codable {
    let lat, lng: Double
}

struct AtcSessionV2: Codable {
    let frequency: Double
    let position: Position
}

enum ConnectionType: String, Codable {
    case atc = "ATC"
}

struct Subcenter: Codable {
    let centerID, atcCallsign: String
    let middleIdentifier: String?
    let position: Position
    let composePosition: String
    let military: Bool
    let frequency, latitude, longitude: Double
    let regionMap: [RegionMap]
    let regionMapPolygon: [[Double]]?
    
    enum CodingKeys: String, CodingKey {
        case centerID = "centerId"
        case atcCallsign, middleIdentifier, position, composePosition, military, frequency, latitude, longitude, regionMap, regionMapPolygon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        centerID = try container.decode(String.self, forKey: .centerID)
        atcCallsign = try container.decode(String.self, forKey: .atcCallsign)
        middleIdentifier = try container.decodeIfPresent(String.self, forKey: .middleIdentifier)
        position = try container.decode(Position.self, forKey: .position)
        composePosition = try container.decode(String.self, forKey: .composePosition)
        if let boolValue = try? container.decode(Bool.self, forKey: .military) {
            military = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .military) {
            military = stringValue == "1" || stringValue.lowercased() == "true"
        } else {
            military = false
        }
        frequency = try container.decode(Double.self, forKey: .frequency)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        regionMap = try container.decode([RegionMap].self, forKey: .regionMap)
        regionMapPolygon = try container.decodeIfPresent([[Double]].self, forKey: .regionMapPolygon)
    }
}

struct Aircraft: Codable {
    let icaoCode: String?
    let model: String?
    let wakeTurbulence: String?
    let description: String?
    let military: String?
}

struct AtcSession: Codable {
    let frequency: Double
    let position: String?
}

struct Atis: Codable {
    let lines: [String]?
    let revision: String?
    let timestamp: String?
}

struct LastTrack: Codable {
    let altitude: Int
    let altitudeDifference: Int
    let latitude: Double
    let longitude: Double
    let heading: Int
    let onGround: Bool
    let state: String
    let timestamp: String
    let transponder: Int
    let transponderMode: String
    let time: Int
    let arrivalDistance: Double?
    let departureDistance: Double?
    let groundSpeed: Int?
}

struct Atc: Codable, Identifiable {
    let id: Int
    let userId: Int
    let callsign: String
    let serverId: String?
    let softwareTypeId: String?
    let softwareVersion: String?
    let rating: Int?
    let createdAt: String?
    let time: Int?
    let atcSession: AtcSession
    let lastTrack: LastTrack?
    let atis: Atis?
    let atcPosition: AtcPosition?
    let subcenter: Subcenter?
}

struct Clients: Codable {
    let atcs: [Atc]
    let pilots: [Pilot]
    let observers: [Atc]?
    let followMe: [Pilot]?
}

struct Root: Codable {
    let updatedAt: String
    let clients: Clients
}

struct RootCountry: Codable {
    var Code: String
    var Country: String
    var CCode: String?
}
struct Connections: Codable {
    let total, supervisor, atc, observer: Int
    let pilot, worldTour, followMe: Int
    let uniqueUsers24h: Int?
}

struct PilotSession: Codable {
    let simulatorId: String?
    let textureId: Int?
}

struct Pilot: Codable {
    let id, userId: Int
    let callsign: String
    let rating: Int?
    let createdAt: String?
    let time: Int?
    let flightPlan: FlightPlan?
    let lastTrack: LastTrack?
    let pilotSession: PilotSession?
    let serverId: String?
    let softwareTypeId: String?
    let softwareVersion: String?
}

struct FlightPlan: Codable {
    let id: Int?
    let revision: Int?
    let aircraftId: String?
    let aircraftNumber: Int?
    let departureId, arrivalId, alternativeId, alternative2Id: String?
    let route: String
    let remarks: String?
    let speed: String
    let level: String
    let flightRules: String?
    let flightType: String?
    let eet, endurance, departureTime: Int
    let actualDepartureTime: Int?
    let peopleOnBoard: Int
    let createdAt: String?
    let aircraftEquipments: String?
    let aircraftTransponderTypes: String?
    let aircraft: Aircraft?
}

struct RouteData {
    let id: UUID
    let departure: CLLocationCoordinate2D
    let current: CLLocationCoordinate2D
    let arrival: CLLocationCoordinate2D
    let departureId: String
    let arrivalId: String
}
