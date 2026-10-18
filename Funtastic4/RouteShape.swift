//
//  RouteShape.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CoreLocation
import MapKit

/// A route small enough to publish to friends: thinned out, then packed into bytes.
enum RouteShape {
    /// The route's line reduced to at most `maxPoints` points, never straying far from the original.
    static func simplify(_ polyline: MKPolyline, maxPoints: Int = 300) -> [CLLocationCoordinate2D] {
        let points = polyline.mapPoints
        var tolerance = 10.0  // meters; doubled until the line is small enough
        var kept = points
        while kept.count > maxPoints {
            kept = douglasPeucker(points, tolerance: tolerance)
            tolerance *= 2
        }
        return kept.map(\.coordinate)
    }

    /// Latitude and longitude as whole microdegrees (about 0.1 m), four bytes each.
    static func encode(_ coordinates: [CLLocationCoordinate2D]) -> Data {
        let values = coordinates.flatMap { [Int32(($0.latitude * 1e6).rounded()), Int32(($0.longitude * 1e6).rounded())] }
        return values.withUnsafeBytes { Data($0) }
    }

    static func decode(_ data: Data) -> [CLLocationCoordinate2D] {
        data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count - 7, by: 8).map { offset in
                CLLocationCoordinate2D(latitude: Double(bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 1e6,
                                       longitude: Double(bytes.loadUnaligned(fromByteOffset: offset + 4, as: Int32.self)) / 1e6)
            }
        }
    }

    /// Keeps the points that matter: drops every point within `tolerance` meters of the line between the points kept around it.
    private static func douglasPeucker(_ points: [MKMapPoint], tolerance: Double) -> [MKMapPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var spans = [(first: 0, last: points.count - 1)]
        while let (first, last) = spans.popLast() {
            var farthest = 0.0
            var index = first
            for i in (first + 1)..<last {
                let distance = points[i].distance(to: points[i].projected(ontoSegmentFrom: points[first], to: points[last]).foot)
                if distance > farthest {
                    farthest = distance
                    index = i
                }
            }
            if farthest > tolerance {
                keep[index] = true
                spans.append((first, index))
                spans.append((index, last))
            }
        }
        return zip(points, keep).filter(\.1).map(\.0)
    }
}
