import SwiftUI
import MapKit
import CoreLocation

struct ATCMapView: View {
    let atcs: [Atc]
    let polygonData: [WelcomeElement]
    let pilots: [Pilot]
    
    @State private var selectedPilot: Pilot?
    @StateObject private var airportManager = AirportDataManager.shared
    @State private var pilotRoutes: [RouteData] = []
    @State private var mapRotation: Double = 0
    @State private var position: MapCameraPosition
    @GestureState private var gestureRotation: Double = 0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isHovering: Bool = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private let towerRadius: CLLocationDegrees = .fromKilometers(9.3)
    
    init(atcs: [Atc], polygonData: [WelcomeElement], pilots: [Pilot]) {
        self.atcs = atcs
        self.polygonData = polygonData
        self.pilots = pilots
        
        let savedLatitude = UserDefaults.standard.double(forKey: "mapLatitude")
        let savedLongitude = UserDefaults.standard.double(forKey: "mapLongitude")
        let savedZoom = UserDefaults.standard.double(forKey: "mapZoom")
        
        if savedLatitude != 0 && savedLongitude != 0 && savedZoom != 0 {
            _position = State(initialValue: .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: savedLatitude, longitude: savedLongitude), distance: savedZoom)))
        } else {
            _position = State(initialValue: .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 39.9334, longitude: 32.8597), distance: 1000000)))
        }
    }
    
    var body: some View {
        Map(position: $position) {
            ForEach(pilots, id: \.id) { pilot in
                if let lastTrack = pilot.lastTrack {
                    Annotation(coordinate: CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude)) {
                        Image("plane")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .rotationEffect(Angle(degrees: Double(lastTrack.heading) - mapRotation))
                            .onTapGesture {
                                if selectedPilot?.id == pilot.id {
                                    clearSelection()
                                } else {
                                    selectedPilot = pilot
                                    updateRoute(for: pilot)
                                }
                            }
                    } label: {
                        Text(pilot.callsign)
                    }
                }
            }
            
            ForEach(atcs, id: \.id) { atc in
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
            }

            ForEach(pilotRoutes, id: \.id) { routeData in
                MapPolyline(coordinates: [routeData.departure, routeData.current])
                    .stroke(.green, lineWidth: 2)
                MapPolyline(coordinates: [routeData.current, routeData.arrival])
                    .stroke(.blue, lineWidth: 2)
                
                Annotation(coordinate: routeData.departure) {
                    Image(systemName: "airplane.departure")
                        .foregroundColor(.green)
                } label: {
                    Text(routeData.departureId)
                }
                
                Annotation(coordinate: routeData.arrival) {
                    Image(systemName: "airplane.arrival")
                        .foregroundColor(.blue)
                } label: {
                    Text(routeData.arrivalId)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .onMapCameraChange { context in
            mapRotation = context.camera.heading
            
            UserDefaults.standard.set(context.camera.centerCoordinate.latitude, forKey: "mapLatitude")
            UserDefaults.standard.set(context.camera.centerCoordinate.longitude, forKey: "mapLongitude")
            UserDefaults.standard.set(context.camera.distance, forKey: "mapZoom")
        }
        .overlay(alignment: .bottom) {
            if let pilot = selectedPilot {
                PilotInfoCard(pilot: pilot, onDismiss: clearSelection)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: selectedPilot?.id)
            }
        }
        .ignoresSafeArea()
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onChange(of: airportManager.lastError) { oldValue, newValue in
            if let error = newValue {
                alertMessage = error
                showAlert = true
            }
        }
    }
    
    private func updateRoute(for pilot: Pilot) {
        if let route = calculateRouteData(for: pilot) {
            pilotRoutes = [route]
        } else {
            pilotRoutes.removeAll()
        }
    }
        
    private func clearSelection() {
        selectedPilot = nil
        pilotRoutes.removeAll()
    }
    
    
    private func calculateRouteData(for pilot: Pilot) -> RouteData? {
        guard let flightPlan = pilot.flightPlan,
              let departureId = flightPlan.departureId,
              let arrivalId = flightPlan.arrivalId,
              let lastTrack = pilot.lastTrack,
              let departureCoords = airportManager.getAirportCoordinates(ident: departureId),
              let arrivalCoords = airportManager.getAirportCoordinates(ident: arrivalId) else {
            return nil
        }
        
        let current = CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude)
        
        return RouteData(
            id: UUID(),
            departure: departureCoords,
            current: current,
            arrival: arrivalCoords,
            departureId: departureId,
            arrivalId: arrivalId
        )
    }
}

// MARK: - Pilot Info Card

struct PilotInfoCard: View {
    let pilot: Pilot
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pilot.callsign)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    if let lastTrack = pilot.lastTrack {
                        Text("ALT \(lastTrack.altitude) ft  ·  HDG \(lastTrack.heading)°  ·  GS \(lastTrack.groundSpeed ?? 0) kt")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)
            
            if let fp = pilot.flightPlan {
                // Route bar
                HStack(spacing: 12) {
                    routeEndpoint(fp.departureId ?? "????", icon: "airplane.departure", color: .green)
                    
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(height: 1)
                    
                    routeEndpoint(fp.arrivalId ?? "????", icon: "airplane.arrival", color: .blue)
                }
                .padding(.bottom, 14)
                
                // Flight details grid
                HStack(spacing: 0) {
                    detailCell(label: "SPD", value: fp.speed)
                    detailCell(label: "FL", value: fp.level)
                    detailCell(label: "EET", value: formatEET(fp.eet))
                    if let alt = fp.alternativeId, !alt.isEmpty {
                        detailCell(label: "ALT", value: alt)
                    }
                }
                .padding(.bottom, 14)
                
                // Route
                if !fp.route.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROUTE")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(fp.route)
                            .font(.system(size: 14, design: .monospaced))
                            .lineLimit(4)
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                }
                
                // Remarks
                if let remarks = fp.remarks, !remarks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RMK")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(remarks)
                            .font(.system(size: 14))
                            .lineLimit(3)
                            .foregroundStyle(.primary.opacity(0.7))
                    }
                    .padding(.top, 8)
                }
            } else {
                Text("No flight plan filed")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .frame(maxWidth: 520)
    }
    
    private func routeEndpoint(_ icao: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(icao)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
        }
    }
    
    private func detailCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatEET(_ eet: Int) -> String {
        let hours = eet / 3600
        let minutes = (eet % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}
