import SwiftUI
import UIKit
import Foundation
import Combine
import MapKit
import SQLite3
import CoreLocation


extension CLLocationDegrees {
    static func fromKilometers(_ km: Double) -> CLLocationDegrees {
        return km / 111.32  // Approximate conversion
    }
}

extension JSONDecoder {
    static func customDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let stringData = try container.decode(String.self)
            guard let data = stringData.data(using: .utf8) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid UTF-8 data"))
            }
            return data
        }
        return decoder
    }
}

extension View {
    func hiddenNavigationBarStyle() -> some View {
        modifier(HiddenNavigationBar())
    }
}

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

struct HiddenNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
    }
}

struct StarShape: Shape {
    let points: Int
    let innerRatio: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let angleIncrement = .pi * 2 / CGFloat(points * 2)
        
        var path = Path()
        
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * angleIncrement - .pi / 2
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

class ATCViewModel: ObservableObject {
    @Published var atcs: [Atc] = []
    @Published var pilots: [Pilot] = []
    @Published var countries: [RootCountry] = []
    @Published var polygonData: [WelcomeElement] = []
    @Published var pilotCounts: [String: (inbound: Int, outbound: Int, inRegion: Int)] = [:]
    
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
            return "us" // Assuming your flag image is named "us.png"
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
        await withCheckedContinuation { continuation in
            fetchATCs()
            continuation.resume()
        }
    }
    
    func fetchPolygonDataAsync() async {
        await withCheckedContinuation { continuation in
            fetchPolygonData()
            continuation.resume()
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
            print("Failed to load countries from JSON")
        }
    }
    
    func fetchPolygonData() {
        guard let url = URL(string: "https://api.ivao.aero/v2/tracker/now/atc/summary") else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { output -> Data in
                return output.data
            }
            .decode(type: [WelcomeElement].self, decoder: JSONDecoder.customDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        print("Error fetching polygon data: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] elements in
                    if !elements.isEmpty {
                        self?.polygonData = elements
                    } else {
                        print("Received empty polygon data, keeping existing data")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func loadJson(filename fileName: String) -> [RootCountry]? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("JSON file not found.")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let jsonData = try decoder.decode([RootCountry].self, from: data)
            return jsonData
        } catch {
            print("Error decoding JSON: \(error.localizedDescription)")
            return nil
        }
    }
    
    func fetchATCs() {
        guard let url = URL(string: "https://api.ivao.aero/v2/tracker/whazzup") else { return }
        
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: Root.self, decoder: JSONDecoder.customDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        print("Error fetching ATCs: \(error.localizedDescription)")
                    }
                },
                receiveValue: { [weak self] root in
                    // Only update if we have new data
                    if !root.clients.atcs.isEmpty {
                        self?.atcs = root.clients.atcs.sorted { $0.callsign < $1.callsign }
                        self?.pilots = root.clients.pilots
                        self?.updatePilotCounts(pilots: root.clients.pilots)
                    } else {
                        print("Received empty ATC data, keeping existing data")
                    }
                }
            )
            .store(in: &cancellables)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel = ATCViewModel()
    @State private var searchText = UserDefaults.standard.string(forKey: "searchText") ?? ""
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var showMap = false
    @State private var timer: Timer?
    @State private var selectedATC: Atc?
    
    var body: some View {
        ZStack {
            Group {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    phoneLayout
                } else {
                    tabletDesktopLayout
                }
            }
            
            if showMap {
                fullScreenMapView
            }
        }
        .onAppear(perform: onAppear)
        .onDisappear {  // Add this modifier
            timer?.invalidate()
        }
        .refreshable {
            await refreshAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification), perform: onWillEnterForeground)
    }
    
    var phoneLayout: some View {
        NavigationView {
            VStack {
                searchBarWithMapButton
                atcCountText
                atcList
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    logoLink
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    var tabletDesktopLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Sidebar
                VStack {
                    logoLink
                    searchBarWithMapButton
                    atcCountText
                    atcList
                }
                .frame(width: geometry.size.width * 0.3)
                .background(Color(UIColor.systemBackground))
                
                // Detail view
                if let atc = selectedATC {
                    ATCDetailViewWrapper(
                        atcId: atc.id,
                        viewModel: viewModel
                    )
                    .id(atc.id)
                    .navigationViewStyle(StackNavigationViewStyle())
                    .frame(width: geometry.size.width * 0.7)
                } else {
                    ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
                        .edgesIgnoringSafeArea(.all)
                        .frame(width: geometry.size.width * 0.7)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                logoLink
            }
        }
    }
    
    var searchBarWithMapButton: some View {
        HStack {
            Button(action: {
                showMap = true
            }) {
                Image(systemName: "map")
                    .foregroundColor(.blue)
            }
            .padding(.leading)
            
            TextField("Search", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: searchText) { oldValue, newValue in
                    searchText = newValue.uppercased()
                    UserDefaults.standard.set(searchText, forKey: "searchText")
                }
        }
        .padding([.top, .horizontal])
    }
    
    var fullScreenMapView: some View {
        ZStack(alignment: .topLeading) {
            ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
                .edgesIgnoringSafeArea(.all)
            
            Button(action: {
                showMap = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding()
            .padding(.top, 0)  // Add top padding to move it below the status bar
            .padding(.leading, 20)
        }
    }
    
    var atcList: some View {
        List(viewModel.atcs.filter { $0.callsign.hasPrefix(searchText) || searchText.isEmpty }, id: \.id) { atc in
            if UIDevice.current.userInterfaceIdiom == .phone {
                NavigationLink(destination: ATCDetailView(
                    atc: atc,
                    polygonData: viewModel.polygonData,
                    cCode: viewModel.countryName(fromCode: String(atc.callsign.prefix(2))).lowercased(),
                    station: viewModel.getStationName(fromCode: String(atc.callsign)),
                    pilots: viewModel.pilots,
                    region: MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: atc.lastTrack.latitude, longitude: atc.lastTrack.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                    ),
                    isIPhone: true
                )) {
                    ATCListItemView(atc: atc, viewModel: viewModel)
                }
            } else {
                ATCListItemView(atc: atc, viewModel: viewModel)
                    .onTapGesture {
                        selectedATC = atc
                    }
            }
        }
    }
    
    private var mapView: some View {
        ZStack(alignment: .topTrailing) {
            ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
            
            Button(action: {
                showMap = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding()
        }
    }
    
    private var searchBar: some View {
        TextField("Search", text: $searchText)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()
            .onChange(of: searchText) { oldValue, newValue in
                searchText = newValue.uppercased()
                UserDefaults.standard.set(searchText, forKey: "searchText")
            }
    }
    
    private var atcCountText: some View {
        Text("Found \(viewModel.atcs.filter { $0.callsign.hasPrefix(searchText) || searchText.isEmpty }.count) ATC(s)")
            .padding(.bottom)
    }
    
    
    
    private var logoLink: some View {
        Link(destination: URL(string: "https://webeye.ivao.aero/")!) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 40)
        }
    }
    
    
    
    private func refreshAction() async {
        await viewModel.loadCountriesAsync()
        await viewModel.fetchATCsAsync()
        await viewModel.fetchPolygonDataAsync()
    }
    
    private func onAppear() {
        Task {
            await viewModel.loadCountriesAsync()
            await viewModel.fetchATCsAsync()
            await viewModel.fetchPolygonDataAsync()
            startTimer()
        }
    }
    
    private func onWillEnterForeground(_ notification: Notification) {
        Task {
            await viewModel.loadCountriesAsync()
            await viewModel.fetchATCsAsync()
            await viewModel.fetchPolygonDataAsync()
            startTimer()
        }
    }
    
    private func startTimer() {
        timer?.invalidate()  // Invalidate any existing timer
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task {
                await refreshAction()
            }
        }
    }
}

struct ATCDetailViewWrapper: View {
    let atcId: Int
    @ObservedObject var viewModel: ATCViewModel
    @State private var region: MKCoordinateRegion
    
    var atc: Atc? {
        viewModel.atcs.first(where: { $0.id == atcId })
    }
    
    init(atcId: Int, viewModel: ATCViewModel) {
        self.atcId = atcId
        self.viewModel = viewModel
        let atc = viewModel.atcs.first(where: { $0.id == atcId })!
        _region = State(initialValue: Self.getRegion(for: atc))
    }
    
    var body: some View {
        Group {
            if let atc = atc {
                ATCDetailView(
                    atc: atc,
                    polygonData: viewModel.polygonData,
                    cCode: viewModel.countryName(fromCode: String(atc.callsign.prefix(2))).lowercased(),
                    station: viewModel.getStationName(fromCode: String(atc.callsign)),
                    pilots: viewModel.pilots,
                    region: region,
                    isIPhone: false                )
            } else {
                Text("ATC not found")
            }
        }
        .onChange(of: atc?.lastTrack.latitude) { oldValue, newValue in
            updateRegion()
        }
        .onChange(of: atc?.lastTrack.longitude) { oldValue, newValue in
            updateRegion()
        }
    }
    
    private func updateRegion() {
        if let atc = atc {
            region = Self.getRegion(for: atc)
        }
    }
    
    private static func getRegion(for atc: Atc) -> MKCoordinateRegion {
        let span = getSpanForPosition(atc.atcSession.position)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: atc.lastTrack.latitude, longitude: atc.lastTrack.longitude),
            span: span
        )
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
}

struct ATCListItemView: View {
    let atc: Atc
    let viewModel: ATCViewModel
    
    var body: some View {
        HStack {
            Image(viewModel.countryName(fromCode: String(atc.callsign.prefix(2))).lowercased())
                .resizable()
                .scaledToFit()
                .frame(height: 60)
                .cornerRadius(5)
                .padding(.trailing, 5)
            VStack(alignment: .leading) {
                Text("\(atc.callsign)")
                    .bold()
                Text(viewModel.getStationName(fromCode: String(atc.callsign)))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("\(viewModel.getCountryName(fromCode: String(atc.callsign.prefix(2))))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(convertSecondsToHHMMSS(atc.lastTrack.time))")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            ATCInfoView(atc: atc, viewModel: viewModel)
        }
    }
    
    private func convertSecondsToHHMMSS(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct ATCInfoView: View {
    let atc: Atc
    let viewModel: ATCViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            Text("\(atc.atis?.revision ?? "N/A")")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            HStack(spacing: 5) {
                if let counts = viewModel.pilotCounts[atc.callsign] {
                    if atc.atcSession.position == "CTR" || atc.atcSession.position == "FSS" {
                        if counts.inRegion != 0 {
                            Text("\(counts.inRegion)")
                                .foregroundColor(.blue)
                        } else {
                            Text("0")
                        }
                    } else {
                        if counts.inbound != 0 && counts.outbound != 0 {
                            Text("\(counts.inbound)")
                                .foregroundColor(.green)
                            Text("/")
                            Text("\(counts.outbound)")
                                .foregroundColor(.red)
                        } else {
                            Text("0")
                        }
                    }
                    
                }
            }
        }
    }
}

struct ATCMapView: View {
    let atcs: [Atc]
    let polygonData: [WelcomeElement]
    let pilots: [Pilot]
    
    @State private var selectedPilot: Pilot?
    @StateObject private var airportManager = AirportDataManager.shared
    @State private var pilotRoutes: [RouteData] = []
    @State private var debugMessage: String = ""
    @State private var mapRotation: Double = 0
    @State private var position: MapCameraPosition = .automatic
    @GestureState private var gestureRotation: Double = 0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isHovering: Bool = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    private let towerRadius: CLLocationDegrees = .fromKilometers(9.3)
    
    var body: some View {
        ZStack {
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
                                    if horizontalSizeClass == .regular {  // Likely a desktop
                                        isHovering = hovering
                                        if hovering {
                                            selectedPilot = pilot
                                            updateRouteAndDebugMessage(for: pilot)
                                        } else {
                                            clearSelection()
                                        }
                                    }
                                }
                                .onTapGesture {
                                    if selectedPilot?.id == pilot.id {
                                        selectedPilot = nil
                                    } else {
                                        selectedPilot = pilot
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
            }
            .ignoresSafeArea()
            
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    
                    if let selectedPilot = selectedPilot,
                       let flightPlan = selectedPilot.flightPlan,
                       let lastTrack = selectedPilot.lastTrack {
                        
                        VStack(alignment: .leading, spacing: 10) {
                            // First row
                            HStack {
                                LabeledContent("Callsign:", value: selectedPilot.callsign)
                                    .font(.system(size: 30))
                                Spacer()
                                LabeledContent("From/To:", value: "\(flightPlan.departureId ?? "N/A") → \(flightPlan.arrivalId ?? "N/A")")
                                    .font(.system(size: 30))
                            }
                            
                            Divider()
                                .background(Color.white)
                                .padding(.vertical, 5)
                            
                            // Second row
                            HStack {
                                LabeledContent("Speed:", value: flightPlan.speed)
                                Spacer()
                                LabeledContent("Flight Level:", value: flightPlan.level)
                                Spacer()
                                LabeledContent("Altitude:", value: "\(lastTrack.altitude) ft")
                                Spacer()
                                LabeledContent("EET:", value: formatEET(flightPlan.eet))
                            }
                            
                            // Third row
                            LabeledContent("Route:", value: flightPlan.route)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .frame(width: geometry.size.width * 0.9)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 30)
            }
            
            // Add a close button for touch devices
            if selectedPilot != nil && horizontalSizeClass == .compact {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: clearSelection) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
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
    
    private func updateRouteAndDebugMessage(for pilot: Pilot) {
        guard let flightPlan = pilot.flightPlan, let lastTrack = pilot.lastTrack else {
            debugMessage = "No flight plan or track data available for \(pilot.callsign)"
            return
        }

        debugMessage = """
        Callsign: \(pilot.callsign) | From/To: \(flightPlan.departureId ?? "N/A") → \(flightPlan.arrivalId ?? "N/A")
        Speed: \(flightPlan.speed) | Flight Level: \(flightPlan.level) | Altitude: \(lastTrack.altitude) ft | EET: \(formatEET(flightPlan.eet))
        Route: \(flightPlan.route)
        """

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
        guard let flightPlan = pilot.flightPlan else {
            //debugMessage += "\nNo flight plan found for pilot: \(pilot.callsign)"
            return nil
        }
        
        guard let departureId = flightPlan.departureId else {
            //debugMessage += "\nNo departure ID found in flight plan"
            return nil
        }
        
        guard let arrivalId = flightPlan.arrivalId else {
            //debugMessage += "\nNo arrival ID found in flight plan"
            return nil
        }
        
        guard let lastTrack = pilot.lastTrack else {
            //debugMessage += "\nNo last track found for pilot"
            return nil
        }
        
        guard let departureCoords = airportManager.getAirportCoordinates(ident: departureId) else {
            //debugMessage += "\nFailed to get coordinates for departure: \(departureId)"
            return nil
        }
        
        guard let arrivalCoords = airportManager.getAirportCoordinates(ident: arrivalId) else {
            //debugMessage += "\nFailed to get coordinates for arrival: \(arrivalId)"
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

struct LabeledContent: View {
    let label: String
    let value: String
    
    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .fontWeight(.bold)
            Text(value)
        }
    }
}

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

#Preview {
    ContentView()
}



// Model Definitions
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

class AirportDataManager: ObservableObject {
    static let shared = AirportDataManager()
    private var db: OpaquePointer?
    
    @Published var lastError: String?
    
    private init() {
        openDatabase()
    }
    
    private func openDatabase() {
        guard let dbPath = Bundle.main.path(forResource: "airport", ofType: "db3") else {
            lastError = "Database file not found in bundle"
            print("Error: \(lastError ?? "")")
            return
        }
        
        print("Attempting to open database at path: \(dbPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            lastError = "Error opening database: \(String(cString: sqlite3_errmsg(db)))"
            print("Error: \(lastError ?? "")")
            return
        }
        
        print("Successfully opened database at \(dbPath)")
    }
    
    func getAirportCoordinates(ident: String) -> CLLocationCoordinate2D? {
        print("Attempting to get coordinates for airport: \(ident)")
        
        guard let db = db else {
            lastError = "Database connection is not initialized"
            print("Error: \(lastError ?? "")")
            return nil
        }
        
        let queryString = "SELECT latitude_deg, longitude_deg FROM airports WHERE ident = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            lastError = "Error preparing statement: \(String(cString: sqlite3_errmsg(db)))"
            print("Error: \(lastError ?? "")")
            return nil
        }
        
        sqlite3_bind_text(statement, 1, (ident as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let latitude = sqlite3_column_double(statement, 0)
            let longitude = sqlite3_column_double(statement, 1)
            sqlite3_finalize(statement)
            print("Found coordinates for \(ident): (\(latitude), \(longitude))")
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        
        sqlite3_finalize(statement)
        lastError = "No coordinates found for airport with ident: \(ident)"
        print("Error: \(lastError ?? "")")
        return nil
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}

// MARK: - MapView

struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let routeData: RouteData?
    let pilots: [Pilot]
    let onPilotSelect: (Pilot) -> Void
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)
        
        // Remove all overlays and annotations
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations)
        
        // Add pilot annotations
        for pilot in pilots {
            if let lastTrack = pilot.lastTrack {
                let annotation = PilotAnnotation(pilot: pilot)
                annotation.coordinate = CLLocationCoordinate2D(latitude: lastTrack.latitude, longitude: lastTrack.longitude)
                uiView.addAnnotation(annotation)
            }
        }
        
        // Add route if available
        if let routeData = routeData {
            let departureToCurrentPolyline = MKPolyline(coordinates: [routeData.departure, routeData.current], count: 2)
            let currentToArrivalPolyline = MKPolyline(coordinates: [routeData.current, routeData.arrival], count: 2)
            
            uiView.addOverlay(departureToCurrentPolyline)
            uiView.addOverlay(currentToArrivalPolyline)
            
            // Add departure and arrival annotations
            let departureAnnotation = MKPointAnnotation()
            departureAnnotation.coordinate = routeData.departure
            departureAnnotation.title = routeData.departureId
            
            let arrivalAnnotation = MKPointAnnotation()
            arrivalAnnotation.coordinate = routeData.arrival
            arrivalAnnotation.title = routeData.arrivalId
            
            uiView.addAnnotations([departureAnnotation, arrivalAnnotation])
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let pilotAnnotation = view.annotation as? PilotAnnotation {
                parent.onPilotSelect(pilotAnnotation.pilot)
            }
        }
    }
}

class PilotAnnotation: NSObject, MKAnnotation {
    let pilot: Pilot
    var coordinate: CLLocationCoordinate2D
    
    init(pilot: Pilot) {
        self.pilot = pilot
        self.coordinate = CLLocationCoordinate2D(latitude: pilot.lastTrack?.latitude ?? 0, longitude: pilot.lastTrack?.longitude ?? 0)
    }
    
    var title: String? {
        return pilot.callsign
    }
}
