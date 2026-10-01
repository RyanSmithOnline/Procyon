//
//  WrappingStack.swift
//  Procyon
//
//  Wrapping row layout.
//
//  Replaces SwiftUI-Flow's `HFlow`. Only the centred variant Procyon used is
//  implemented, which keeps it small enough to read.
//

import SwiftUI

/// Lays children out left to right, wrapping onto new lines when the row is full.
struct WrappingStack: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .center

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        var y = bounds.minY + max(0, (bounds.height - totalHeight) / 2)

        for row in rows {
            var x = bounds.minX
            let rowWidth = row.width
            // Centre each row within the available width.
            x += max(0, (bounds.width - rowWidth) * alignmentOffset)
            for item in row.items {
                let size = bounds.width.isFinite
                    ? subviews[item].sizeThatFits(.unspecified)
                    : subviews[item].sizeThatFits(
                        ProposedViewSize(width: rowWidth, height: nil)
                    )
                subviews[item].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private var alignmentOffset: CGFloat {
        switch alignment {
        case .center: return 0.5
        case .trailing: return 1.0
        default: return 0.0
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        // Probe with the real available width so wrapping matches what gets drawn.
        let childProposal = maxWidth.isFinite ? ProposedViewSize(width: maxWidth, height: nil) : ProposedViewSize(width: nil, height: nil)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(childProposal)
            let projected = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if !current.items.isEmpty, projected > maxWidth {
                rows.append(current)
                current = Row()
                current.items = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.items.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}