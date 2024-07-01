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



#Preview {
    ContentView()
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
