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
    let connectionType: String
    let atcSession: AtcSessionV2
    let atcPosition: AtcPosition?
    let subcenter: Subcenter?
}

struct AtcPosition: Codable {
    let airportId: String  // Changed from airportID to airportId
    let atcCallsign: String
    let military: Bool
    let middleIdentifier: String?
    let position, composePosition: String
    let regionMap: [RegionMap]
    let regionMapPolygon: [[Double]]
    let airport: Airport
    
    enum CodingKeys: String, CodingKey {
        case airportId  // This should match the JSON key exactly
        case atcCallsign, military, middleIdentifier, position, composePosition, regionMap, regionMapPolygon, airport
    }
}

struct Airport: Codable {
    let icao: String
    let iata: String?
    let name, countryID, city: String
    let latitude, longitude: Double
    let military: Bool
    
    enum CodingKeys: String, CodingKey {
        case icao, iata, name
        case countryID = "countryId"
        case city, latitude, longitude, military
    }
}

enum Position: String, Codable {
    case app = "APP"
    case ctr = "CTR"
    case del = "DEL"
    case gnd = "GND"
    case twr = "TWR"
    case fss = "FSS"  // Add this new case
    case unknown      // Add an unknown case for any other values
    
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
    let regionMapPolygon: [[Double]]
    
    enum CodingKeys: String, CodingKey {
        case centerID = "centerId"
        case atcCallsign, middleIdentifier, position, composePosition, military, frequency, latitude, longitude, regionMap, regionMapPolygon
    }
}

struct Aircraft: Codable {
    let icaoCode: String?
    let model: String?
    let wakeTurbulence: String?
    let description: String?
}

struct AtcSession: Codable {
    let frequency: Double
    let position: String
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
    let heading : Int
    let onGround: Bool
    let state: String
    let timestamp: String
    let transponder: Int
    let transponderMode: String
    let time: Int
}

struct Atc: Codable, Identifiable {
    let id: Int
    let userId: Int
    let callsign: String
    let serverId: String
    let softwareTypeId: String
    let softwareVersion: String
    let rating: Int
    let createdAt: String
    let time: Int
    let atcSession: AtcSession
    let lastTrack: LastTrack
    let atis: Atis?
    let atcPosition: AtcPosition?
    let subcenter: Subcenter?
}

struct Clients: Codable {
    let atcs: [Atc]
    let pilots: [Pilot]
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
}

struct Pilot: Codable {
    let id, userId: Int
    let callsign: String
    let rating: Int
    let createdAt: String
    let time: Int
    let flightPlan: FlightPlan?
    let lastTrack: LastTrack?
}

struct FlightPlan: Codable {
    let departureId, arrivalId, alternativeId, alternative2ID: String?
    let route, remarks, speed, level: String
    let eet, endurance, departureTime: Int
    let peopleOnBoard: Int
    let createdAt: String
    let aircraftEquipments, aircraftTransponderTypes: String
}

struct RouteData {
    let id: UUID
    let departure: CLLocationCoordinate2D
    let current: CLLocationCoordinate2D
    let arrival: CLLocationCoordinate2D
    let departureId: String
    let arrivalId: String
}
