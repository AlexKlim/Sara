import Foundation

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Double {
    var degrees: String { formatted(.number.precision(.fractionLength(0...1))) + "°" }
    var degreesTenths: String { formatted(.number.precision(.fractionLength(1))) + "°" }
}
