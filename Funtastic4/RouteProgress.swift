//
//  RouteProgress.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CoreLocation
import MapKit

/// Where a GPS fix sits on a route, and what the next turn is. Pure geometry, no UI.
///
/// MapKit steps read "drive this far, then do the instruction", so a step's instruction belongs at the
/// end of the step's line.
struct RouteProgress {
    struct Fix {
        /// Meters from the start of the route to the closest point on it.
        var along: CLLocationDistance
        /// Meters from the fix to that point.
        var offRoute: CLLocationDistance
    }

    struct Maneuver {
        /// The junction's position, so the same turn keeps its id when the route is refreshed.
        var id: String
        var instruction: String
        /// Meters from the fix to the junction.
        var distance: CLLocationDistance
    }

    let route: MKRoute
    private let path: Path
    private let turns: [(id: String, instruction: String, along: CLLocationDistance)]

    var length: CLLocationDistance { path.length }

    init(_ route: MKRoute) {
        let path = Path(route.polyline.mapPoints)
        var turns: [(id: String, instruction: String, along: CLLocationDistance)] = []
        var from: CLLocationDistance = 0
        for step in route.steps where !step.instructions.isEmpty {
            guard let end = step.polyline.mapPoints.last else { continue }
            // Locating each junction on the same line as the rider keeps both measured the same way.
            from = path.closest(to: end, in: from...path.length).along
            let coordinate = end.coordinate
            turns.append((String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude), step.instructions, from))
        }
        self.route = route
        self.path = path
        self.turns = turns
    }

    /// Projects a fix onto the route. `hint` is the previous position along it: looking near the hint first
    /// stops a route that doubles back on itself from snapping the rider onto the wrong leg.
    func locate(_ coordinate: CLLocationCoordinate2D, near hint: CLLocationDistance) -> Fix {
        let target = MKMapPoint(coordinate)
        let nearby = path.closest(to: target, in: max(0, hint - 200)...(hint + 5_000))
        return nearby.offRoute <= 100 ? nearby : path.closest(to: target, in: 0...path.length)
    }

    func nextManeuver(after along: CLLocationDistance) -> Maneuver? {
        turns.first { $0.along > along + 1 }
            .map { Maneuver(id: $0.id, instruction: $0.instruction, distance: $0.along - along) }
    }
}

/// The route's line with the distance from the start to every point on it.
private struct Path {
    let points: [MKMapPoint]
    let cumulative: [CLLocationDistance]

    var length: CLLocationDistance { cumulative.last ?? 0 }

    init(_ points: [MKMapPoint]) {
        var total: CLLocationDistance = 0
        self.points = points
        cumulative = [0] + zip(points, points.dropFirst()).map { a, b in
            total += a.distance(to: b)
            return total
        }
    }

    /// The closest point on the line to `target`, looking only at the part of the line inside `range`.
    func closest(to target: MKMapPoint, in range: ClosedRange<CLLocationDistance>) -> RouteProgress.Fix {
        var best = RouteProgress.Fix(along: range.lowerBound, offRoute: .infinity)
        for i in points.indices.dropLast() where cumulative[i + 1] >= range.lowerBound && cumulative[i] <= range.upperBound {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : min(1, max(0, ((target.x - a.x) * dx + (target.y - a.y) * dy) / lengthSquared))
            let offRoute = target.distance(to: MKMapPoint(x: a.x + t * dx, y: a.y + t * dy))
            if offRoute < best.offRoute {
                best = RouteProgress.Fix(along: cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), offRoute: offRoute)
            }
        }
        return best
    }
}

private extension MKPolyline {
    var mapPoints: [MKMapPoint] { Array(UnsafeBufferPointer(start: points(), count: pointCount)) }
}
