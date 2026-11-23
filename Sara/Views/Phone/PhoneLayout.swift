import CoreGraphics

/// How the phone screen is laid out, from its size: one column, or two halves either side of the fold of an
/// unfolded Duo (or of a phone on its side).
struct PhoneLayout: Equatable {
    enum Split { case none, columns, rows }
    let split: Split
    /// The inner screen of a Duo: the halves keep clear of the fold.
    let unfolded: Bool

    init(_ size: CGSize) {
        unfolded = min(size.width, size.height) >= 600
        let landscape = size.width > size.height
        split = landscape ? .columns : unfolded ? .rows : .none
    }
}
