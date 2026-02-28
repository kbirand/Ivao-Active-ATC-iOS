import SwiftUI
import Foundation
import MapKit
import SQLite3
import CoreLocation

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
            #if DEBUG
            print("Error: \(lastError ?? "")")
            #endif
            return
        }
        
        #if DEBUG
        print("Attempting to open database at path: \(dbPath)")
        #endif
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            lastError = "Error opening database: \(String(cString: sqlite3_errmsg(db)))"
            #if DEBUG
            print("Error: \(lastError ?? "")")
            #endif
            return
        }
        
        #if DEBUG
        print("Successfully opened database at \(dbPath)")
        #endif
    }
    
    func getAirportCoordinates(ident: String) -> CLLocationCoordinate2D? {
        #if DEBUG
        print("Attempting to get coordinates for airport: \(ident)")
        #endif
        
        guard let db = db else {
            lastError = "Database connection is not initialized"
            #if DEBUG
            print("Error: \(lastError ?? "")")
            #endif
            return nil
        }
        
        let queryString = "SELECT latitude_deg, longitude_deg FROM airports WHERE ident = ?"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, queryString, -1, &statement, nil) == SQLITE_OK else {
            lastError = "Error preparing statement: \(String(cString: sqlite3_errmsg(db)))"
            #if DEBUG
            print("Error: \(lastError ?? "")")
            #endif
            return nil
        }
        
        sqlite3_bind_text(statement, 1, (ident as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let latitude = sqlite3_column_double(statement, 0)
            let longitude = sqlite3_column_double(statement, 1)
            sqlite3_finalize(statement)
            #if DEBUG
            print("Found coordinates for \(ident): (\(latitude), \(longitude))")
            #endif
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        
        sqlite3_finalize(statement)
        lastError = "No coordinates found for airport with ident: \(ident)"
        #if DEBUG
        print("Error: \(lastError ?? "")")
        #endif
        return nil
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}

// MARK: - MapView (UIKit bridge)

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
