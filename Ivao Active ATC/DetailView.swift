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
    var onClose: (() -> Void)? = nil
    
    @State private var mapRotation: Double = 0
    
    init(atc: Atc, polygonData: [WelcomeElement], cCode: String, station: String, pilots: [Pilot], region: MKCoordinateRegion, isIPhone: Bool, onClose: (() -> Void)? = nil) {
        self.atc = atc
        self.polygonData = polygonData
        self.cCode = cCode
        self.station = station
        self.pilots = pilots
        self.region = region
        self.isIPhone = isIPhone
        self.onClose = onClose
    }
    
    var body: some View {
        ZStack {
            // Full-bleed map behind everything
            atcMap
                .ignoresSafeArea()
            
            // Floating info card
            if isIPhone {
                phoneOverlay
            } else {
                desktopOverlay
            }
        }
        .navigationTitle(isIPhone ? atc.callsign : "")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Desktop Overlay
    
    private var desktopOverlay: some View {
        VStack {
            HStack {
                Spacer()
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                }
            }
            Spacer()
            HStack {
                floatingInfoCard
                    .frame(maxWidth: 520)
                Spacer()
            }
        }
        .padding(20)
    }
    
    // MARK: - Phone Overlay
    
    private var phoneOverlay: some View {
        VStack {
            Spacer()
            floatingInfoCard
        }
        .padding(12)
    }
    
    // MARK: - Floating Info Card
    
    private var floatingInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 16) {
                Image(cCode)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 52)
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(atc.callsign)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(station)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                // ATIS badge
                if let revision = atc.atis?.revision {
                    Text(revision)
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.accentColor.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.bottom, 20)
            
            // Stats row
            HStack(spacing: 0) {
                statCell(value: atc.atcSession.position ?? "—", label: "POSITION")
                statDivider
                statCell(value: String(format: "%.3f", atc.atcSession.frequency), label: "FREQUENCY")
                statDivider
                statCell(value: convertSecondsToHHMMSS(atc.lastTrack?.time ?? 0), label: "ACTIVE")
            }
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // ATIS section
            if let lines = atc.atis?.lines, !lines.isEmpty {
                let atisText = lines
                    .filter { !$0.contains("ivao.aero/") }
                    .joined(separator: " ")
                if !atisText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ATIS")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .tracking(1.5)
                            Spacer()
                            if let ts = atc.atis?.timestamp {
                                Text(formatTimestamp(ts))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        
                        Text(atisText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 16)
                }
            }
            
            // Coordinates
            if let lastTrack = atc.lastTrack {
                HStack(spacing: 16) {
                    Text("\(String(format: "%.4f", lastTrack.latitude))° N")
                    Text("\(String(format: "%.4f", abs(lastTrack.longitude)))° \(lastTrack.longitude >= 0 ? "E" : "W")")
                }
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 14)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
    }
    
    // MARK: - Stat Cell
    
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: 40)
    }
    
    private func formatTimestamp(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: ts) {
            let df = DateFormatter()
            df.dateFormat = "HHmm'z'"
            df.timeZone = TimeZone(abbreviation: "UTC")
            return df.string(from: date)
        }
        return ""
    }
    
    // MARK: - Map
    
    private var atcMap: some View {
        Map(initialPosition: MapCameraPosition.region(region)) {
            if let relevantPolygon = polygonData.first(where: { $0.callsign == atc.callsign }),
               let lastTrack = atc.lastTrack {
                switch relevantPolygon.atcSession.position {
                case .twr:
                    MapCircle(center: CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude),
                              radius: CLLocationDegrees.fromKilometers(9.3) * 111320)
                    .stroke(.red, lineWidth: 2)
                    .foregroundStyle(.red.opacity(0.1))
                case .gnd:
                    MapPolygon(coordinates: createStarCoordinates(
                        center: CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude),
                        radius: CLLocationDegrees.fromKilometers(9.3) * 111320,
                        points: 4,
                        rotation: 0
                    ))
                    .stroke(.yellow, lineWidth: 2)
                    .foregroundStyle(.yellow.opacity(0.1))
                case .del:
                    MapPolygon(coordinates: createStarCoordinates(
                        center: CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude),
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
                        Image("plane")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .rotationEffect(Angle(degrees: Double(lastTrack.heading) - mapRotation))
                    } label: {
                        Text(pilot.callsign)
                    }
                }
            }
            
            if let lastTrack = atc.lastTrack {
                Annotation(coordinate: CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude)) {
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
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onMapCameraChange { context in
            mapRotation = context.camera.heading
        }
    }
    
}
