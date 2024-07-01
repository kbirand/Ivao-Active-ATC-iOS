import SwiftUI
import UIKit
import Foundation
import Combine
import MapKit
import SQLite3
import CoreLocation

struct ATCDetailView: View {
    let atc: Atc
    let polygonData: [WelcomeElement]
    let cCode: String
    let station: String
    let pilots: [Pilot]
    let region: MKCoordinateRegion
    let isIPhone: Bool
    
    @State private var mapRotation: Double = 0
    @ObservedObject var viewModel = ATCViewModel()
    
    init(atc: Atc, polygonData: [WelcomeElement], cCode: String, station: String, pilots: [Pilot], region: MKCoordinateRegion, isIPhone: Bool) {
        self.atc = atc
        self.polygonData = polygonData
        self.cCode = cCode
        self.station = station
        self.pilots = pilots
        self.region = region
        self.isIPhone = isIPhone
    }
    
    var body: some View {
        VStack(spacing: -5) {
            // Top section
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(cCode)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 60)  // Adjust width and height as needed
                        .cornerRadius(5)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text(atc.callsign)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(station)
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Position:").bold()
                        Text("\(atc.atcSession.position)")
                    }
                    HStack {
                        Text("Latitude:").bold()
                        Text("\(atc.lastTrack.latitude)")
                    }
                    HStack {
                        Text("Longitude:").bold()
                        Text("\(atc.lastTrack.longitude)")
                    }
                    HStack {
                        Text("Frequency:").bold()
                        Text("\(atc.atcSession.frequency)")
                    }
                    HStack {
                        Text("ATIS Info:").bold()
                        Text("\(atc.atis?.revision ?? "N/A")")
                    }
                    HStack {
                        Text("Active Time:").bold()
                        Text("\(convertSecondsToHHMMSS(atc.lastTrack.time))")
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            
            // Map section
            Map(initialPosition: MapCameraPosition.region(region)) {
                if let relevantPolygon = polygonData.first(where: { $0.callsign == atc.callsign }) {
                    switch relevantPolygon.atcSession.position {
                    case .twr:
                        MapCircle(center: CLLocationCoordinate2D(latitude: atc.lastTrack.latitude, longitude: atc.lastTrack.longitude),
                                  radius: CLLocationDegrees.fromKilometers(9.3) * 111320)
                        .stroke(.red, lineWidth: 2)
                        .foregroundStyle(.red.opacity(0.1))
                    case .gnd:
                        MapPolygon(coordinates: createStarCoordinates(
                            center: CLLocationCoordinate2D(latitude: atc.lastTrack.latitude, longitude: atc.lastTrack.longitude),
                            radius: CLLocationDegrees.fromKilometers(9.3) * 111320,
                            points: 4,
                            rotation: 0
                        ))
                        .stroke(.yellow, lineWidth: 2)
                        .foregroundStyle(.yellow.opacity(0.1))
                    case .del:
                        MapPolygon(coordinates: createStarCoordinates(
                            center: CLLocationCoordinate2D(latitude: atc.lastTrack.latitude, longitude: atc.lastTrack.longitude),
                            radius: CLLocationDegrees.fromKilometers(9.3) * 111320,
                            points: 4,
                            rotation: .pi / 4
                        ))
                        .stroke(Color(red: 1, green: 1, blue: 0.8), lineWidth: 2)
                        .foregroundStyle(Color(red: 1, green: 1, blue: 0.8).opacity(0.2))
                    case .app, .ctr, .fss:
                        if let polygonCoordinates = getPolygonCoordinates(for: relevantPolygon), !polygonCoordinates.isEmpty {
                            MapPolygon(coordinates: polygonCoordinates)
                                .stroke(.blue, lineWidth: 2)
                                .foregroundStyle(.blue.opacity(0.1))
                        }
                    default:
                        EmptyMapContent()
                    }
                }
                
                ForEach(pilots, id: \.id) { pilot in
                    if let lastTrack = pilot.lastTrack {
                        Annotation(coordinate: CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude)) {
                            Image("plane") // Use "plane" if you have a custom image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .rotationEffect(Angle(degrees: Double(lastTrack.heading) - mapRotation))
                        } label: {
                            Text(pilot.callsign)
                        }
                    }
                }
                
                Annotation(coordinate: CLLocationCoordinate2D(latitude: atc.lastTrack.latitude, longitude: atc.lastTrack.longitude)) {
                    Text(atc.callsign)
                        .font(.system(size: 10, weight: .regular))
                        .padding(5)
                        .background(Color.black.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(5)
                } label: {
                    EmptyView()
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .padding(.horizontal)
            .onMapCameraChange { context in
                mapRotation = context.camera.heading
            }
            
            Spacer()
            
            // Bottom section
            VStack(alignment: .leading, spacing: 0) {
                Text("ATIS Details:")
                    .font(.headline)
                Text(atc.atis?.lines?.dropFirst(2).joined(separator: "\n").dropFirst() ?? "No ATIS available")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 14, weight: .regular))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(isIPhone ? atc.callsign + " Details" : "")
        .navigationBarTitleDisplayMode(isIPhone ? .inline : .automatic)
    }
    
    private static func getSpanForPosition(_ position: String) -> MKCoordinateSpan {
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
    
    private func convertSecondsToHHMMSS(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func getPolygonCoordinates(for element: WelcomeElement) -> [CLLocationCoordinate2D]? {
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
    
    private func normalizeLongitude(_ longitude: Double) -> Double {
        var normalized = longitude
        while normalized < -180 {
            normalized += 360
        }
        while normalized > 180 {
            normalized -= 360
        }
        return normalized
    }
    
    private func createStarCoordinates(center: CLLocationCoordinate2D, radius: CLLocationDegrees, points: Int, rotation: Double) -> [CLLocationCoordinate2D] {
        let angleIncrement = .pi * 2 / Double(points * 2)
        return (0..<(points * 2)).map { i in
            let angle = Double(i) * angleIncrement - .pi / 2 + rotation
            let r = i % 2 == 0 ? radius : radius * 0.3
            let lat = center.latitude + (cos(angle) * r) / 111320
            let lon = center.longitude + (sin(angle) * r) / (111320 * cos(center.latitude * .pi / 180))
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
}
