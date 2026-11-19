import SwiftUI
import UniformTypeIdentifiers

/// One section: icons right-aligned like in the menu bar; icons can be dropped anywhere in it.
struct SectionRow: View {
    private static let ROW_HEIGHT: CGFloat = 88

    let section: BarSection
    @ObservedObject var model: BarModel
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var isDropTargeted = false

    private var coordinateSpaceName: String { "row-\(section.rawValue)" }

    var body: some View {
        let items = model.sections[section] ?? []
        TrailingFlowLayout(spacing: 6) {
            if section == .shown {
                // The app's own dot stays next to shown items and must remain accessible.
                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
                    .frame(width: 32, height: 40)
                    .help("Tuck")
            }
            ForEach(items) { item in
                MenuBarItemImage(item: item)
                    .padding(.horizontal, 8)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                    .help(item.displayName)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: TileFramesKey.self, value: [item.id: proxy.frame(in: .named(coordinateSpaceName))])
                    })
                    .onDrag { NSItemProvider(object: item.id as NSString) }
            }
            if section == .shown {
                // System icons are shown for orientation but cannot be moved.
                ForEach(model.fixedItems) { item in
                    MenuBarItemImage(item: item).padding(.horizontal, 8).frame(height: 40).help(item.displayName)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Self.ROW_HEIGHT)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.primary.opacity(isDropTargeted ? 0.10 : 0.03))
        )
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(TileFramesKey.self) { tileFrames = $0 }
        .onDrop(of: [UTType.text], delegate: RowDropDelegate(
            section: section, model: model, tileFrames: tileFrames, isTargeted: $isDropTargeted
        ))
        .opacity(model.isSorting ? 0.5 : 1)
    }
}

/// Picture of an item as it looks in the menu bar, or a neutral placeholder until capture succeeds.
struct MenuBarItemImage: View {
    let item: MenuBarItem

    var body: some View {
        if let image = MenuBarIconPresentation.image(for: item) {
            Image(nsImage: image)
        } else {
            Text(item.displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 100)
                .help("Снимок иконки трея пока недоступен: " + item.displayName)
        }
    }
}

/// Frames of icon tiles inside one row, keyed by item id.
private struct TileFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    /// Merges tile frames reported by the views in the row.
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Turns a drop position into "insert before the n-th icon of this section".
private struct RowDropDelegate: DropDelegate {
    let section: BarSection
    let model: BarModel
    let tileFrames: [String: CGRect]
    @Binding var isTargeted: Bool

    /// Highlights the row when a dragged item enters it.
    func dropEntered(info: DropInfo) { isTargeted = true }
    /// Removes the highlight when a dragged item leaves the row.
    func dropExited(info: DropInfo) { isTargeted = false }

    /// Uses a move operation while the item is over the row.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Loads the dragged item and inserts it at the indicated position.
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        let dropPoint = info.location
        let frames = tileFrames
        let section = section
        let model = model
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let itemID = object as? String else { return }
            Task { @MainActor in
                // Count icons (other than the dragged one) that come before the drop point in reading order.
                let sectionIDs = (model.sections[section] ?? []).map(\.id).filter { $0 != itemID }
                let index = sectionIDs.filter { id in
                    guard let frame = frames[id] else { return false }
                    let isOnEarlierLine = frame.maxY < dropPoint.y
                    let isEarlierOnSameLine = frame.minY <= dropPoint.y && frame.midX < dropPoint.x
                    return isOnEarlierLine || isEarlierOnSameLine
                }.count
                model.place(itemID: itemID, in: section, at: index)
            }
        }
        return true
    }
}

/// Lays views out in lines like text, each line pushed to the right edge (like the menu bar).
private struct TrailingFlowLayout: Layout {
    let spacing: CGFloat

    /// Measures the space required by the wrapped rows.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lineBreaks(for: subviews, width: width)
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    /// Places each line of tiles against the right edge.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var lineTop = bounds.minY
        for line in lineBreaks(for: subviews, width: bounds.width) {
            // Right-align each line.
            var x = bounds.maxX - line.width
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: lineTop + (line.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            lineTop += line.height + spacing
        }
    }

    /// One line of subviews and its size.
    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Splits subviews into lines that fit `width`.
    private func lineBreaks(for subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithItem = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if widthWithItem > width && !current.indices.isEmpty {
                lines.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = widthWithItem
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}
