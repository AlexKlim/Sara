import SwiftUI

/// Lays views out in rows like words of centered text.
struct CenteredFlow: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for (index, width) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [(items: [(index: Int, width: CGFloat)], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [(index: Int, width: CGFloat)], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.items + [(index, size.width)], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([(index, size.width)], size.width, size.height))
            }
        }
        return rows
    }
}
