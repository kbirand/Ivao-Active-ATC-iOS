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
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.openURL) private var openURL
    @State private var showMap = false
    @State private var timer: Timer?
    @State private var selectedATC: Atc?
    /// The sliding list panel in narrow portrait.
    @State private var showSidebar = true
    
    /// The iPad layout (list beside the map) whenever the window is regular in both directions:
    /// iPad full screen and iPhone Duo unfolded. iPhones, the Duo folded and narrow iPad
    /// split views use the phone layout.
    private var useWideLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            Group {
                if !useWideLayout {
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
            if geometry.size.width >= geometry.size.height {
                // Landscape: list beside the map, wide enough for a full row
                let sidebarWidth = min(max(geometry.size.width * 0.3, 340), geometry.size.width * 0.45)
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: sidebarWidth)
                    mapPane
                        .frame(width: geometry.size.width - sidebarWidth)
                }
            } else if geometry.size.width < 800 {
                // Narrow portrait (iPhone Duo unfolded, iPad mini): full map, list slides in from the left
                let panelWidth = min(340, geometry.size.width * 0.6)
                ZStack(alignment: .leading) {
                    mapPane
                    // The panel with its pull tab; hidden, only the tab shows at the map's edge
                    HStack(spacing: 0) {
                        sidebar
                            .frame(width: panelWidth)
                        Button {
                            withAnimation(.snappy) { showSidebar.toggle() }
                        } label: {
                            Image(systemName: showSidebar ? "chevron.compact.left" : "chevron.compact.right")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 72)
                                .background(
                                    Color(UIColor.systemBackground),
                                    in: UnevenRoundedRectangle(bottomTrailingRadius: 12, topTrailingRadius: 12)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showSidebar ? "Hide list" : "Show list")
                    }
                    .shadow(color: .black.opacity(0.5), radius: 12)
                    .offset(x: showSidebar ? 0 : -panelWidth)
                    .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                        if value.translation.width < -60 { withAnimation(.snappy) { showSidebar = false } }
                        if value.translation.width > 60 { withAnimation(.snappy) { showSidebar = true } }
                    })
                }
                .onChange(of: selectedATC?.id) { _, id in
                    if id != nil { withAnimation(.snappy) { showSidebar = false } }
                }
            } else {
                // Wide portrait (bigger iPads): list beside the map
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 340)
                    mapPane
                        .frame(width: geometry.size.width - 340)
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

    private var sidebar: some View {
        VStack {
            logoLink
                .padding(.top, 8)
            searchBarWithMapButton
            atcCountText
            atcList
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
    }

    /// The map with the selected station's card on top.
    private var mapPane: some View {
        ZStack {
            ATCMapView(atcs: viewModel.atcs, polygonData: viewModel.polygonData, pilots: viewModel.pilots)
                .ignoresSafeArea(edges: [.top, .trailing])

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

            Menu {
                Button("Contact Support", systemImage: "envelope") {
                    Task { openURL(await SupportLink.url()) }
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.blue)
            }
            .accessibilityLabel("Help")
            .padding(.trailing)
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
            if !useWideLayout {
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
                    // The plain list leaves no trailing inset here, which clips the letter column
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
                .frame(width: 90, height: 60)
                .cornerRadius(5)
                .padding(.trailing, 5)
            VStack(alignment: .leading) {
                Text("\(atc.callsign)")
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
            Spacer(minLength: 4)
            ATCInfoView(atc: atc, viewModel: viewModel)
                .fixedSize()
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

