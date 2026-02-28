import SwiftUI
import MapKit
import CoreLocation

// MARK: - Shared Helper Functions

func convertSecondsToHHMMSS(_ totalSeconds: Int) -> String {
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
}

func getPolygonCoordinates(for element: WelcomeElement) -> [CLLocationCoordinate2D]? {
    let coordinates: [RegionMap]?
    if let regionMap = element.atcPosition?.regionMap {
        coordinates = regionMap
    } else if let regionMap = element.subcenter?.regionMap {
        coordinates = regionMap
    } else {
        return nil
    }
    
    return coordinates?.compactMap { coordinate in
        let normalizedLng = normalizeLongitude(coordinate.lng)
        return CLLocationCoordinate2D(latitude: coordinate.lat, longitude: normalizedLng)
    }
}

func normalizeLongitude(_ longitude: Double) -> Double {
    var normalized = longitude
    while normalized < -180 {
        normalized += 360
    }
    while normalized > 180 {
        normalized -= 360
    }
    return normalized
}

func createStarCoordinates(center: CLLocationCoordinate2D, radius: CLLocationDegrees, points: Int, rotation: Double) -> [CLLocationCoordinate2D] {
    let angleIncrement = .pi * 2 / Double(points * 2)
    return (0..<(points * 2)).map { i in
        let angle = Double(i) * angleIncrement - .pi / 2 + rotation
        let r = i % 2 == 0 ? radius : radius * 0.3
        let lat = center.latitude + (cos(angle) * r) / 111320
        let lon = center.longitude + (sin(angle) * r) / (111320 * cos(center.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

func getSpanForPosition(_ position: String) -> MKCoordinateSpan {
    switch position.lowercased() {
    case "twr":
        return MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
    case "app":
        return MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 2.5)
    case "gnd":
        return MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
    case "del":
        return MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
    case "ctr", "fss":
        return MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 25)
    default:
        return MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    }
}
