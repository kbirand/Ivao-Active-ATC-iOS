import SwiftUI
import UIKit
import Foundation
import MapKit
import CoreLocation


extension CLLocationDegrees {
    static func fromKilometers(_ km: Double) -> CLLocationDegrees {
        return km / 111.32  // Approximate conversion
    }
}


extension View {
    func hiddenNavigationBarStyle() -> some View {
        modifier(HiddenNavigationBar())
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
            
            if let error = viewModel.errorMessage {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.caption)
                            .lineLimit(2)
                        Spacer()
                        Button(action: { viewModel.errorMessage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: viewModel.errorMessage)
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
                
                // Map + Detail overlay
                ZStack {
                    ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
                        .edgesIgnoringSafeArea(.all)
                    
                    if let atc = selectedATC {
                        ATCDetailViewWrapper(
                            atcId: atc.id,
                            viewModel: viewModel,
                            onClose: { selectedATC = nil }
                        )
                        .id(atc.id)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: selectedATC?.id)
                    }
                }
                .frame(width: geometry.size.width * 0.7)
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
        ZStack(alignment: .topTrailing) {
            ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
                .edgesIgnoringSafeArea(.all)
            
            Button(action: {
                showMap = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            .padding(20)
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
                        center: CLLocationCoordinate2D(latitude: atc.lastTrack?.latitude ?? 0, longitude: atc.lastTrack?.longitude ?? 0),
                        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                    ),
                    isIPhone: true
                )) {
                    ATCListItemView(atc: atc, viewModel: viewModel)
                }
            } else {
                ATCListItemView(atc: atc, viewModel: viewModel)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedATC = atc
                    }
                    .listRowBackground(
                        selectedATC?.id == atc.id ? Color.accentColor.opacity(0.2) : Color.clear
                    )
            }
        }
        .listStyle(.plain)
    }
    
    private var mapView: some View {
        ZStack(alignment: .topTrailing) {
            ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
            
            Button(action: {
                showMap = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            .padding(20)
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
        Link(destination: URL(string: "https://webeye.ivao.aero/") ?? URL(string: "https://ivao.aero")!) {
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
    var onClose: (() -> Void)? = nil
    
    var atc: Atc? {
        viewModel.atcs.first(where: { $0.id == atcId })
    }
    
    init(atcId: Int, viewModel: ATCViewModel, onClose: (() -> Void)? = nil) {
        self.atcId = atcId
        self.viewModel = viewModel
        self.onClose = onClose
        if let atc = viewModel.atcs.first(where: { $0.id == atcId }) {
            _region = State(initialValue: Self.getRegion(for: atc))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            ))
        }
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
                    isIPhone: false,
                    onClose: onClose
                )
            } else {
                Text("ATC not found")
            }
        }
        .onChange(of: atc?.lastTrack?.latitude) { oldValue, newValue in
            updateRegion()
        }
        .onChange(of: atc?.lastTrack?.longitude) { oldValue, newValue in
            updateRegion()
        }
    }
    
    private func updateRegion() {
        if let atc = atc {
            region = Self.getRegion(for: atc)
        }
    }
    
    private static func getRegion(for atc: Atc) -> MKCoordinateRegion {
        let span = getSpanForPosition(atc.atcSession.position ?? "")
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: atc.lastTrack?.latitude ?? 0, longitude: atc.lastTrack?.longitude ?? 0),
            span: span
        )
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
                Text("\(convertSecondsToHHMMSS(atc.lastTrack?.time ?? 0))")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            ATCInfoView(atc: atc, viewModel: viewModel)
        }
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
                    if atc.atcSession.position == "CTR" || atc.atcSession.position == "FSS" || atc.atcSession.position == nil {
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


#Preview {
    ContentView()
}

