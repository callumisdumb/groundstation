import AppKit
import MapKit
import SwiftUI

/// MapKit map with real aircraft position, home marker, flight track,
/// and offline waypoint route. No invented position is ever displayed.
struct GroundStationMap: NSViewRepresentable {
    var aircraft: CLLocationCoordinate2D?
    var home: CLLocationCoordinate2D?
    var route: [MissionWaypoint]
    var flightTrack: [CLLocationCoordinate2D]
    var satellite: Bool
    var followAircraft: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.mapType = .hybrid
        view.showsCompass = true
        view.showsScale = true
        view.pointOfInterestFilter = .excludingAll
        view.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 54.5, longitude: -3),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 5)), animated: false)
        return view
    }

    func updateNSView(_ view: MKMapView, context: Context) {
        view.mapType = satellite ? .hybrid : .standard
        let annotations = view.annotations.filter { !($0 is MKUserLocation) }
        view.removeAnnotations(annotations)
        view.removeOverlays(view.overlays)

        if let aircraft, CLLocationCoordinate2DIsValid(aircraft) {
            let a = MKPointAnnotation()
            a.title = "Aircraft"
            a.coordinate = aircraft
            view.addAnnotation(a)
            if followAircraft {
                let visible = view.region
                let center = visible.center
                let change = abs(center.latitude - aircraft.latitude) +
                    abs(center.longitude - aircraft.longitude)
                if change > 0.0005 {
                    view.setCenter(aircraft, animated: true)
                }
            }
        }
        if let home, CLLocationCoordinate2DIsValid(home) {
            let pin = MKPointAnnotation()
            pin.title = "Home"
            pin.coordinate = home
            view.addAnnotation(pin)
        }
        for (index, waypoint) in route.enumerated() {
            let pin = MKPointAnnotation()
            pin.title = "WP \(index + 1)"
            pin.subtitle = "\(Int(waypoint.altitudeMeters)) m"
            pin.coordinate = waypoint.coordinate
            view.addAnnotation(pin)
        }

        if route.count >= 2 {
            let points = route.map(\.coordinate)
            let line = MKPolyline(coordinates: points, count: points.count)
            line.title = "planned"
            view.addOverlay(line)
        }
        if flightTrack.count >= 2 {
            let line = MKPolyline(coordinates: flightTrack, count: flightTrack.count)
            line.title = "track"
            view.addOverlay(line)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let id = "GroundStationPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id)
                as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(
                    annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.canShowCallout = true
            if annotation.title ?? nil == "Aircraft" {
                view.markerTintColor = .systemTeal
                view.glyphImage = NSImage(systemSymbolName: "airplane", accessibilityDescription: "Aircraft")
            } else if annotation.title ?? nil == "Home" {
                view.markerTintColor = .systemGreen
                view.glyphImage = NSImage(systemSymbolName: "house.fill", accessibilityDescription: "Home")
            } else {
                view.markerTintColor = .systemOrange
                view.glyphText = annotation.title ?? nil
                view.glyphImage = nil
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.title == "planned" ? .systemOrange : .systemTeal
            renderer.lineWidth = line.title == "planned" ? 3.5 : 2.5
            renderer.alpha = 0.88
            return renderer
        }
    }
}
