import AppKit
import MapKit
import SwiftUI

struct MapRequest {
    enum Action {
        case center(CLLocationCoordinate2D)
        case fit([CLLocationCoordinate2D])
        case zoom(Double)
        case overview
    }
    let action: Action
    let id = UUID()
}

struct GroundStationMap: NSViewRepresentable {
    var aircraft: CLLocationCoordinate2D?
    var home: CLLocationCoordinate2D?
    var route: [MissionWaypoint]
    var flightTrack: [CLLocationCoordinate2D]
    var satellite: Bool
    var followAircraft: Bool
    var request: MapRequest? = nil

    private static let overview = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.5, longitude: -3),
        span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 5))

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier("GroundStationMap")
        view.mapType = satellite ? .hybrid : .standard
        view.showsCompass = true
        view.showsScale = true
        view.pointOfInterestFilter = .excludingAll
        view.setRegion(Self.overview, animated: false)
        return view
    }

    func updateNSView(_ view: MKMapView, context: Context) {
        let type: MKMapType = satellite ? .hybrid : .standard
        if view.mapType != type { view.mapType = type }
        context.coordinator.update(view, map: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var aircraftPin: MKPointAnnotation?
        private var homePin: MKPointAnnotation?
        private var waypointPins: [MKPointAnnotation] = []
        private var lastRoute: [MissionWaypoint] = []
        private var lastTrack: [CLLocationCoordinate2D] = []
        private var routeLine: MKPolyline?
        private var trackLine: MKPolyline?
        private var followed = false
        private var lastRequest: UUID?

        func update(_ view: MKMapView, map: GroundStationMap) {
            let previous = aircraftPin?.coordinate
            aircraftPin = updatePin(aircraftPin, at: map.aircraft, title: "Aircraft", on: view)
            homePin = updatePin(homePin, at: map.home, title: "Home", on: view)

            if lastRoute != map.route {
                lastRoute = map.route
                view.removeAnnotations(waypointPins)
                waypointPins = map.route.enumerated().compactMap { index, point in
                    guard CLLocationCoordinate2DIsValid(point.coordinate) else { return nil }
                    let pin = MKPointAnnotation()
                    pin.coordinate = point.coordinate
                    pin.title = "Waypoint \(index + 1)"
                    pin.subtitle = String(format: "%.0f m", point.altitudeMeters)
                    return pin
                }
                view.addAnnotations(waypointPins)
                routeLine = replace(routeLine, with: waypointPins.map(\.coordinate), name: "route", on: view)
            }
            if !lastTrack.elementsEqual(map.flightTrack, by: Self.samePoint) {
                lastTrack = map.flightTrack
                trackLine = replace(trackLine, with: lastTrack, name: "track", on: view)
            }

            if let request = map.request, request.id != lastRequest {
                lastRequest = request.id
                switch request.action {
                case .center(let point): center(point, on: view)
                case .overview: view.setRegion(GroundStationMap.overview, animated: true)
                case .fit(let coordinates):
                    let points = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
                    guard let first = points.first else { break }
                    let line = MKPolyline(coordinates: points, count: points.count)
                    let rect = line.boundingMapRect
                    if points.count == 1 || (rect.width < 1 && rect.height < 1) {
                        center(first, on: view)
                    } else {
                        let padding = NSEdgeInsets(top: 70, left: 55, bottom: 65, right: 65)
                        view.setVisibleMapRect(rect, edgePadding: padding, animated: true)
                    }
                case .zoom(let factor):
                    let old = view.visibleMapRect
                    let width = min(max(96, old.width * factor), MKMapRect.world.width)
                    let height = width * old.height / max(1, old.width)
                    view.setVisibleMapRect(MKMapRect(x: old.midX - width / 2, y: old.midY - height / 2,
                                                     width: width, height: height), animated: true)
                }
            } else if map.followAircraft, let point = aircraftPin?.coordinate {
                if !followed || previous == nil { center(point, on: view) }
                else if let previous, !Self.samePoint(previous, point) { view.setCenter(point, animated: true) }
            }
            followed = map.followAircraft
        }

        private static func samePoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            a.latitude == b.latitude && a.longitude == b.longitude
        }

        private func center(_ coordinate: CLLocationCoordinate2D, on view: MKMapView) {
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
            view.setRegion(region, animated: true)
        }

        private func updatePin(_ existing: MKPointAnnotation?, at coordinate: CLLocationCoordinate2D?,
                               title: String, on view: MKMapView) -> MKPointAnnotation? {
            guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
                if let existing { view.removeAnnotation(existing) }
                return nil
            }
            if let existing {
                if !Self.samePoint(existing.coordinate, coordinate) { existing.coordinate = coordinate }
                return existing
            }
            let pin = MKPointAnnotation()
            pin.title = title
            pin.coordinate = coordinate
            view.addAnnotation(pin)
            return pin
        }

        private func replace(_ old: MKPolyline?, with points: [CLLocationCoordinate2D],
                             name: String, on view: MKMapView) -> MKPolyline? {
            if let old { view.removeOverlay(old) }
            guard points.count > 1 else { return nil }
            let line = MKPolyline(coordinates: points, count: points.count)
            line.title = name
            view.addOverlay(line)
            return line
        }

        func mapViewWillStartLoadingMap(_ mapView: MKMapView) {
            mapView.setAccessibilityValue("Loading map")
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered { mapView.setAccessibilityValue("Map ready") }
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            mapView.setAccessibilityValue("Basemap unavailable")
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? MKPointAnnotation else { return nil }
            let id = "GroundStationPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            view.canShowCallout = true
            view.glyphImage = nil
            view.glyphText = nil
            switch pin.title {
            case "Aircraft":
                view.markerTintColor = .systemBlue
                view.glyphImage = NSImage(systemSymbolName: "location.north.fill", accessibilityDescription: "Aircraft")
            case "Home":
                view.markerTintColor = .systemOrange
                view.glyphImage = NSImage(systemSymbolName: "house.fill", accessibilityDescription: "Home")
            default:
                view.markerTintColor = .systemGreen
                view.glyphText = pin.title?.components(separatedBy: " ").last
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.title == "route" ? .systemGreen : .systemBlue
            renderer.lineWidth = line.title == "route" ? 3.5 : 3
            return renderer
        }
    }
}
