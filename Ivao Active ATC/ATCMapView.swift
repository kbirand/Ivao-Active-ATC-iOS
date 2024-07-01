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
    @State private var debugMessage: String = ""
    @State private var mapRotation: Double = 0
    @State private var position: MapCameraPosition
    @GestureState private var gestureRotation: Double = 0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isHovering: Bool = false
    @State private var showDebugMessage = false
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
                            .onHover { hovering in
                                if horizontalSizeClass == .regular {
                                    if hovering {
                                        selectedPilot = pilot
                                        Task {
                                            await updateRouteAndDebugMessage(for: pilot)
                                        }
                                    } else {
                                        clearSelection()
                                    }
                                }
                            }
                            .onTapGesture {
                                if selectedPilot?.id == pilot.id {
                                    clearSelection()
                                } else {
                                    selectedPilot = pilot
                                    Task {
                                        await updateRouteAndDebugMessage(for: pilot)
                                    }
                                }
                            }
                    } label: {
                        Text(pilot.callsign)
                    }
                }
            }
            
            ForEach(atcs, id: \.id) { atc in
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
            if let _ = selectedPilot, showDebugMessage {
                if let imageData = Data(base64Encoded: debugMessage),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 150)
                        .padding()
                }
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
    
    private func updateRouteAndDebugMessage(for pilot: Pilot) async {
        guard let flightPlan = pilot.flightPlan, let lastTrack = pilot.lastTrack else {
            debugMessage = "No flight plan or track data available for \(pilot.callsign)"
            showDebugMessage = true
            return
        }

        let formattedMessage = VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Callsign: \(pilot.callsign)")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("From/To: \(flightPlan.departureId ?? "N/A") -> \(flightPlan.arrivalId ?? "N/A")")
                    .font(.system(size: 16, weight: .bold))
            }
            
            Divider()
            
            HStack {
                Text("Speed: \(flightPlan.speed)")
                Spacer()
                Text("Flight Level: \(flightPlan.level)")
                Spacer()
                Text("EET: \(formatEET(flightPlan.eet))")
            }
            .font(.system(size: 14))
            
            Text("Route: \(flightPlan.route)")
                .font(.system(size: 14, weight: .bold))
            
            ScrollView(.vertical, showsIndicators: true) {
                Text(flightPlan.route)
                    .font(.system(size: 12))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 60)  // Fixed height for route area
        }
        .frame(width: 300)  // Fixed width for the entire message
        .padding()
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(10)

        debugMessage = await formattedMessage.toAttributedString()
        showDebugMessage = true

        if let route = calculateRouteData(for: pilot) {
            pilotRoutes = [route]
        }
    }

    private func formatEET(_ eet: Int) -> String {
        let hours = eet / 3600
        let minutes = (eet % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
        
    private func clearSelection() {
        selectedPilot = nil
        pilotRoutes.removeAll()
        debugMessage = ""
        showDebugMessage = false
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

extension View {
    func toAttributedString() async -> String {
        await MainActor.run {
            let renderer = ImageRenderer(content: self)
            renderer.scale = UIScreen.main.scale
            if let uiImage = renderer.uiImage {
                if let data = uiImage.pngData() {
                    return data.base64EncodedString()
                }
            }
            return ""
        }
    }
}
