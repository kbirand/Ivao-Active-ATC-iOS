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
    /// Smaller card for a short or narrow map area (iPhone Duo unfolded, iPad mini).
    @State private var compact = false
    /// Full height of the ATIS text, for the compact card's scroll area.
    @State private var atisHeight: CGFloat = 54

    /// The full size on a big iPad, the second value when `compact`.
    private func size(_ full: CGFloat, _ small: CGFloat) -> CGFloat { compact ? small : full }
    
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
        ZStack {
            // Close button: stays inside the safe area, clear of the status pill
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
            }
            .padding(size(20, 10))

            // Card. Compact: bottom right corner, into the bottom and trailing safe areas, so it
            // sits low and out of the way without covering the Maps logo on the left.
            VStack {
                Spacer()
                HStack {
                    if compact { Spacer() }
                    floatingInfoCard
                        .frame(maxWidth: size(520, 280))
                    if !compact { Spacer() }
                }
            }
            .padding(size(20, 10))
            .ignoresSafeArea(.container, edges: compact ? [.bottom, .trailing] : [])
        }
        .onGeometryChange(for: Bool.self) { $0.size.height < 800 || $0.size.width < 700 } action: { compact = $0 }
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
            HStack(alignment: .top, spacing: size(16, 8)) {
                Image(cCode)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size(72, 30), height: size(52, 21))
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(atc.callsign)
                        .font(.system(size: size(28, 15), weight: .heavy))
                        .foregroundStyle(.white)
                    Text(station)
                        .font(.system(size: size(17, 11), weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                // ATIS badge
                if let revision = atc.atis?.revision {
                    Text(revision)
                        .font(compact ? .system(size: 15, weight: .semibold) : .largeTitle)
                        .foregroundStyle(.white)
                        .frame(width: size(54, 24), height: size(54, 24))
                        .background(Color.accentColor.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: size(12, 8), style: .continuous))
                }
            }
            .padding(.bottom, size(20, 7))
            
            // Stats row
            HStack(spacing: 0) {
                statCell(value: atc.atcSession.position ?? "—", label: "POSITION")
                statDivider
                statCell(value: String(format: "%.3f", atc.atcSession.frequency), label: "FREQUENCY")
                statDivider
                statCell(value: convertSecondsToHHMMSS(atc.lastTrack?.time ?? 0), label: "ACTIVE")
            }
            .padding(.vertical, size(16, 5))
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: size(12, 8), style: .continuous))
            
            // ATIS section
            if let lines = atc.atis?.lines, !lines.isEmpty {
                let atisText = lines
                    .filter { !$0.contains("ivao.aero/") }
                    .joined(separator: " ")
                if !atisText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ATIS")
                                .font(.system(size: size(14, 9), weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .tracking(1.5)
                            Spacer()
                            if let ts = atc.atis?.timestamp {
                                Text(formatTimestamp(ts))
                                    .font(.system(size: size(14, 9)))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        
                        let atis = Text(atisText)
                            .font(.system(size: size(16, 10.5), weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(size(6, 1))
                            .fixedSize(horizontal: false, vertical: true)
                        if compact {
                            // About four lines show; the rest scrolls, nothing is cut
                            ScrollView {
                                atis
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { atisHeight = $0 }
                            }
                            .frame(height: min(atisHeight, 54))
                            .scrollBounceBehavior(.basedOnSize)
                            .scrollIndicators(.visible)
                        } else {
                            atis
                        }
                    }
                    .padding(.top, size(16, 6))
                }
            }
            
            // Coordinates
            if let lastTrack = atc.lastTrack {
                HStack(spacing: 16) {
                    Text("\(String(format: "%.4f", lastTrack.latitude))° N")
                    Text("\(String(format: "%.4f", abs(lastTrack.longitude)))° \(lastTrack.longitude >= 0 ? "E" : "W")")
                }
                .font(.system(size: size(14, 9), design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, size(14, 4))
            }
        }
        .padding(size(24, 10))
        .background(cardShape.fill(.black.opacity(0.7)).background(.ultraThinMaterial, in: cardShape))
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
    }
    
    /// Compact: corners concentric with the display, so the corner that sits in the screen's
    /// rounded corner follows its curve; the others stay at 14. Full size: plain 20.
    private var cardShape: AnyShape {
        compact
            ? AnyShape(ConcentricRectangle(corners: .concentric(minimum: 14), isUniform: false))
            : AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Stat Cell
    
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: size(5, 1)) {
            Text(value)
                .font(.system(size: size(20, 11), weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: size(11, 7), weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.1))
            .frame(width: 1, height: size(40, 18))
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
