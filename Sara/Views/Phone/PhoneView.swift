import SwiftUI

/// The phone screen from the design: the panel's blocks in one column, or in two halves either side of a Duo's fold.
/// The sections are the system tab bar: at the bottom of a phone, beside the system buttons on a Duo.
struct PhoneView: View {
    let home: Home
    let panel: Panel
    /// Last exchange of the conversation in progress. nil once it is closed.
    let lastTurn: Turn?
    /// Now, to the minute.
    let date: Date
    let onTalk: () -> Void
    let onSettings: () -> Void

    /// Settings and talking to Sara open over the panel, so their tabs act and leave Home selected.
    private enum Place { case home, settings, talk }
    @State private var place = Place.home

    /// What one column shows, in the order of the design. Two halves follow each block's column instead.
    private enum Part: CaseIterable { case header, running, lights, climate, sliders, turn, other }

    var body: some View {
        TabView(selection: $place) {
            Tab("Home", systemImage: "house", value: Place.home) { page }
            Tab("Settings", systemImage: "slider.horizontal.3", value: Place.settings) { Theme.background }
            Tab("Talk to Sara", systemImage: "mic", value: Place.talk) { Theme.background }
        }
        .tint(Theme.teal)
        .onChange(of: place) {
            guard place != .home else { return }
            Log.write("[phone] tab \(place)")
            if place == .talk { onTalk() } else { onSettings() }
            place = .home
        }
    }

    private var page: some View {
        GeometryReader { geometry in
            // Only the size and the fold are read here, never the safe area: the scroll views below adjust their
            // safe area to the tab bar, and a layout that followed it would go round in circles.
            let size = geometry.size
            let layout = PhoneLayout(size)
            let edge: CGFloat = layout.unfolded ? 24 : size.width > 420 ? 20 : 16
            // The halves sit either side of the fold the system reports. Without one (a phone on its side),
            // either side of the middle.
            let fold = Self.fold(geometry)
            let gap: CGFloat = layout.unfolded ? 40 : 16
            let divide = fold?.frame ?? CGRect(x: size.width / 2 - gap / 2, y: size.height / 2 - gap / 2, width: gap, height: gap)
            // Half folded, each half is a page of its own. Flat, the halves scroll together as one page.
            let pages = fold?.active == true
            // On its side the screen has no strip at the top, so the content starts a little lower; it scrolls away.
            let top: CGFloat = layout.split == .columns ? (layout.unfolded ? 16 : 8) : 0
            // Blocks go to the half their column in the panel settings says, as on the wall panel.
            // A room left without tiles would show only its title.
            let shown = panel.blocks.filter { $0.kind != .room || !$0.items.isEmpty }
            let first = half(shown.filter { $0.column == 0 }, first: true, layout)
            let second = half(shown.filter { $0.column != 0 }, first: false, layout)
            switch layout.split {
            case .none:
                scroll { column(Part.allCases, layout).padding(.horizontal, edge) }
            case .columns where pages:
                HStack(spacing: divide.width) {
                    scroll(top: top) { first.padding(.leading, edge) }.frame(width: max(divide.minX, 0))
                    scroll(top: top) { second.padding(.trailing, edge) }
                }
            case .columns:
                scroll(top: top) {
                    HStack(alignment: .top, spacing: divide.width) {
                        first.frame(width: max(divide.minX - edge, 0))
                        second
                    }
                    .padding(.horizontal, edge)
                }
            case .rows where pages:
                VStack(spacing: divide.height) {
                    scroll { first.padding(.horizontal, edge) }.frame(height: max(divide.minY, 0))
                    scroll { second.padding(.horizontal, edge) }
                }
            case .rows:
                scroll {
                    VStack(alignment: .leading, spacing: divide.height) {
                        first.frame(minHeight: divide.minY, alignment: .top)
                        second
                    }
                    .padding(.horizontal, edge)
                }
            }
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .environment(\.compactPanel, true)
    }

    /// The fold of a Duo as the system reports it, in this view's coordinates. Active while the Duo is half folded.
    private static func fold(_ geometry: GeometryProxy) -> (frame: CGRect, active: Bool)? {
        guard #available(iOS 27.1, *), let region = geometry.reservedRegions(kind: .division, options: .includeInactive).first else { return nil }
        return (region.frame, region.isActive)
    }

    private func scroll(top: CGFloat = 0, @ViewBuilder _ content: () -> some View) -> some View {
        ScrollView { content() }
            .scrollIndicators(.hidden)
            .contentMargins(.top, top, for: .scrollContent)
            .contentMargins(.bottom, 16, for: .scrollContent)
    }

    private func column(_ parts: [Part], _ layout: PhoneLayout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(parts, id: \.self) { part($0, layout) }
        }
        .padding(.top, 8)
    }

    /// One half: the header and the conversation with the first, the timers on top of the second.
    private func half(_ blocks: [PanelBlock], first: Bool, _ layout: PhoneLayout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if first { part(.header, layout) } else { AlarmsBlockView(alarms: .shared) }
            ForEach(blocks) { block in
                switch block.kind {
                case .running:
                    RunningBlockView(block: block, home: home, columns: layout.split == .columns ? 1 : 2)
                        .unreachable(home.offline && block.usesHomeAssistant)
                case .room:
                    section(Text(verbatim: block.title)) {
                        LazyVGrid(columns: Self.grid(layout), spacing: 8) { ForEach(block.items) { TileView(item: $0, home: home) } }
                    }
                    .unreachable(home.offline && block.usesHomeAssistant)
                default:
                    BlockView(block: block, home: home)
                }
            }
            if first { part(.turn, layout) }
        }
        .padding(.top, 8)
    }

    private static func grid(_ layout: PhoneLayout) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: layout.split == .rows ? 3 : 2)
    }

    @ViewBuilder private func part(_ part: Part, _ layout: PhoneLayout) -> some View {
        switch part {
        case .header:
            PhoneHeader(date: date, wide: layout.unfolded)
            if let device = NewDevices.shared.found.first { NewDeviceBanner(device: device) }
            if home.offline { OfflineBanner() }
            if panel.blocks.isEmpty { Text("Set up the panel in Settings").foregroundStyle(Theme.secondary).padding(.top, 40) }
        case .running:
            ForEach(blocks(.running)) {
                RunningBlockView(block: $0, home: home, columns: layout.split == .columns ? 1 : 2)
                    .unreachable(home.offline && $0.usesHomeAssistant)
            }
        case .lights:
            lights(layout)
        case .climate:
            ForEach(blocks(.climate)) { BlockView(block: $0, home: home) }
        case .sliders:
            ForEach(blocks(.slider)) { BlockView(block: $0, home: home) }
        case .turn:
            if let lastTurn { turn(lastTurn) }
        case .other:
            AlarmsBlockView(alarms: .shared)
            ForEach(panel.blocks.filter { [.device, .list].contains($0.kind) }) { BlockView(block: $0, home: home) }
        }
    }

    private func blocks(_ kind: PanelBlock.Kind) -> [PanelBlock] { panel.blocks.filter { $0.kind == kind } }

    /// Room tiles. A phone shows all rooms in one grid and names the room on each tile;
    /// the unfolded Duo on its side has room for a section per room.
    /// Room tiles in one column: all rooms share one grid, and each tile names its room.
    @ViewBuilder private func lights(_ layout: PhoneLayout) -> some View {
        let rooms = blocks(.room).filter { !$0.items.isEmpty }
        if !rooms.isEmpty {
            section(Text("Lights")) {
                LazyVGrid(columns: Self.grid(layout), spacing: 8) {
                    ForEach(rooms) { room in
                        ForEach(room.items) {
                            TileView(item: $0, home: home, room: room.title).unreachable(home.offline && room.usesHomeAssistant)
                        }
                    }
                }
            }
        }
    }

    private func section(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title.blockTitle(size: 13)
            content()
        }
    }

    /// The conversation in progress: what was said and Sara's answer. Tap to open it.
    private func turn(_ turn: Turn) -> some View {
        Button(action: onTalk) {
            HStack(spacing: 12) {
                Image(systemName: "mic").font(.system(size: 18)).foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "«\(turn.user)» · \(turn.date.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Text(verbatim: turn.reply ?? "...").font(.system(size: 15, weight: .medium)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.tealBackground, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.tealBorder))
            .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
    }
}
