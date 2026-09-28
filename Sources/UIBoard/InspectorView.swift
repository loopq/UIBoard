import SwiftUI
import UIBoardCore

struct InspectorView: View {
    @Environment(EditorModel.self) private var model
    @FocusState private var focusedCard: Int?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Issues").font(.system(size: 13, weight: .semibold))
                    CountBadge(count: model.marks.count)
                }
                if model.marks.isEmpty {
                    emptyHint
                } else {
                    cards
                }
            }
            .padding([.horizontal, .top], 16)
            .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            ReferencesSection()
                .padding(16)
        }
        .frame(width: 340)
        .background(Color.panel)
        .onChange(of: model.focusRequest) {
            guard let request = model.focusRequest else { return }
            focusedCard = request
            model.focusRequest = nil
        }
        .onChange(of: focusedCard) {
            if let focusedCard { model.selected = focusedCard }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "cursorarrow.click").font(.system(size: 20))
            Text("Click to pin · Drag to frame")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(model.marks.indices), id: \.self) { index in
                        IssueCard(index: index,
                                  note: noteBinding(index),
                                  selected: model.selected == index,
                                  focus: $focusedCard,
                                  onSelect: { model.selected = index },
                                  onDelete: { model.delete(at: index) })
                            .id(index)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selected) {
                if let selected = model.selected { withAnimation { proxy.scrollTo(selected) } }
            }
        }
    }

    private func noteBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { model.marks.indices.contains(index) ? model.marks[index].note : "" },
            set: { if model.marks.indices.contains(index) { model.marks[index].note = $0 } }
        )
    }
}

private struct IssueCard: View {
    let index: Int
    @Binding var note: String
    let selected: Bool
    var focus: FocusState<Int?>.Binding
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(rgb: Palette.rgb(at: index))))
            TextField("Describe what looks wrong", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...10)
                .lineSpacing(4)
                .focused(focus, equals: index)
                .onExitCommand { focus.wrappedValue = nil }
        }
        .padding(.leading, 12)
        .padding(.trailing, 28)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.selbg : Color.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : Color.cardline, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if hovering || selected {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.trailing, 8)
                .help("Delete #\(index + 1)")
                .accessibilityLabel("Delete issue \(index + 1)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

private struct ReferencesSection: View {
    @Environment(EditorModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("References").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                CountBadge(count: model.refs.count)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(model.refs.indices), id: \.self) { index in
                        RefThumb(image: model.refs[index]) { model.refs.remove(at: index) }
                    }
                    Button { model.addRefs(ImageSource.open(multiple: true)) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16))
                            .frame(width: 64, height: 142)
                            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(dropTargeted ? Color.accentColor : Color.dash, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Add reference image — or drop / paste one")
                    .accessibilityLabel("Add reference image")
                }
            }
            .scrollIndicators(.never)
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Figma URL", text: $model.figmaURL).textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .padding(.top, 4)
        }
        .onDrop(of: ImageSource.dropTypes, isTargeted: $dropTargeted) { providers in
            Task { model.addRefs(await ImageSource.load(providers)) }
            return true
        }
    }
}

private struct RefThumb: View {
    let image: CGImage
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 64, height: 142, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.shotline))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("Remove reference")
                }
            }
            .onHover { hovering = $0 }
    }
}
