// Self-check for PhoneLayout against the screens of the design. Run from the repo root:
// swiftc -parse-as-library -o /tmp/phonelayoutcheck Sara/Views/Phone/PhoneLayout.swift Checks/PhoneLayoutCheck.swift && /tmp/phonelayoutcheck
import CoreGraphics

@main
enum PhoneLayoutCheck {
    static func main() {
        func layout(_ width: CGFloat, _ height: CGFloat) -> PhoneLayout { PhoneLayout(CGSize(width: width, height: height)) }
        // iPhone 18 Pro and Pro Max, and the closed Duo upright: one column.
        for phone in [layout(402, 874), layout(440, 956), layout(466, 678)] {
            assert(phone.split == .none && !phone.unfolded)
        }
        // Duo closed on its side: two columns.
        assert(layout(678, 466).split == .columns && !layout(678, 466).unfolded)
        // Duo open: halves either side of the fold, side by side or one over the other.
        assert(layout(951, 669).split == .columns && layout(951, 669).unfolded)
        assert(layout(669, 951).split == .rows && layout(669, 951).unfolded)
        print("PhoneLayout: ok")
    }
}
