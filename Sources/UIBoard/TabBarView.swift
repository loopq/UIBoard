import SwiftUI
import UIBoardCore

struct TabBarView: View {
    @Environment(EditorModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(model.boards) { board in
                        TabChip(board: board, selected: board.id == model.currentID)
                            .id(board.id)
                        Divider().frame(height: 18)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: model.currentID) {
                if let id = model.currentID { withAnimation { proxy.scrollTo(id) } }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
        .background(Color.panel)
        .overlay(alignment: .bottom) { Divider() }
        .overlay { if dropTargeted { Rectangle().strokeBorder(Color.accentColor, lineWidth: 2) } }
        .onDrop(of: ImageSource.dropTypes, isTargeted: $dropTargeted) { providers in
            Task { model.open(await ImageSource.load(providers), to: .newBoard) }
            return true
        }
    }
}

private struct TabChip: View {
    @Environment(EditorModel.self) private var model
    let board: Board
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ForEach(board.frames) { frame in
                    Image(decorative: frame.image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.shotline))
            Text(board.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 170, alignment: .leading)
            if board.isExported {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                    .help("Exported")
            } else if !board.marks.isEmpty {
                CountBadge(count: board.marks.count)
            }
            Button { model.requestClose(board.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering || selected ? 1 : 0)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close \(board.title)")
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(selected ? Color.canvas : .clear)
        .overlay(alignment: .bottom) {
            if selected { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(board: board.id) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Close Tab") { model.requestClose(board.id) }
        }
    }
}
