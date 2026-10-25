import SwiftUI

struct StretchRoutineEditor: View {
    let routine: StretchRoutine
    let onSave: ([StretchEntry]?) -> Bool
    let onAction: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [StretchEntry]
    @State private var removed: (Int, StretchEntry)?
    @State private var picking = false
    @State private var replacing: String?
    @State private var area = "all"
    @State private var requirement = "any"
    @State private var failure: String?

    init(routine: StretchRoutine, onSave: @escaping ([StretchEntry]?) -> Bool, onAction: @escaping (String) -> Void) {
        self.routine = routine
        self.onSave = onSave
        self.onAction = onAction
        _entries = State(initialValue: routine.entries)
    }
    private var preview: StretchRoutine {
        StretchRoutine(id: routine.id, preferenceID: routine.preferenceID, title: routine.title, entries: entries, customized: true)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(routine.title).font(.headline)
                    Text(preview.calculatedDuration)
                    Text(preview.requirements).font(.caption)
                    if entries.isEmpty { Text(stretchCatalogText("ui.empty")) }
                }
                Section {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if let definition = StretchCatalog.definition(entry.movementID) {
                            HStack(spacing: 12) {
                                StretchPostureIllustration(cue: entry.movementID + (definition.bilateral ? "_left" : "_both"))
                                    .frame(width: 56, height: 64)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(definition.title).font(.subheadline.weight(.medium))
                                    if definition.bilateral { Text(stretchCatalogText("ui.both_sides")).font(.caption).foregroundStyle(.secondary) }
                                    if !definition.requirements.isEmpty { Text(definition.requirements).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(minLength: 0)
                                Menu {
                                    Picker(stretchCatalogText(definition.bilateral ? "ui.duration" : "ui.duration_both"), selection: Binding(get: { entries.first { $0.id == entry.id }?.seconds ?? entry.seconds }, set: { value in
                                        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].seconds = value; onAction("duration") }
                                    })) {
                                        ForEach(StretchCatalog.durations, id: \.self) { Text(Duration.seconds($0).formatted(.time(pattern: .minuteSecond))).tag($0) }
                                    }
                                } label: { Text(Duration.seconds(entry.seconds).formatted(.time(pattern: .minuteSecond))).monospacedDigit() }
                                .accessibilityLabel(stretchCatalogText(definition.bilateral ? "ui.duration" : "ui.duration_both"))
                                Menu {
                                    Button(stretchCatalogText("ui.replace")) { replacing = entry.id; area = definition.area; picking = true }
                                    Button(stretchCatalogText("ui.up")) { entries.swapAt(index, index - 1); onAction("reorder") }.disabled(index == 0)
                                    Button(stretchCatalogText("ui.down")) { entries.swapAt(index, index + 1); onAction("reorder") }.disabled(index == entries.count - 1)
                                    Button(stretchCatalogText("ui.remove"), role: .destructive) { removed = (index, entries.remove(at: index)); onAction("remove") }
                                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 32, minHeight: 44) }
                                .accessibilityLabel(definition.title)
                            }
                        }
                    }
                    .onMove { source, destination in entries.move(fromOffsets: source, toOffset: destination); onAction("reorder") }
                }
                Section {
                    Button(stretchCatalogText("ui.add")) { replacing = nil; area = "all"; picking = true }.disabled(entries.count >= 20)
                    if entries.count >= 20 { Text(stretchCatalogText("ui.limit")) }
                    if let removed {
                        Button(stretchCatalogText("ui.undo")) { entries.insert(removed.1, at: min(removed.0, entries.count)); self.removed = nil; onAction("undo") }.disabled(entries.count >= 20 || entries.contains { $0.id == removed.1.id })
                    }
                    Button(stretchCatalogText("ui.reset"), role: .destructive) { if onSave(nil) { dismiss() } else { failure = stretchCatalogText("ui.failed") } }
                }
            }
            .navigationTitle(stretchCatalogText("ui.editor"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(stretchCatalogText("ui.cancel")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(stretchCatalogText("ui.save")) {
                        if onSave(entries) { dismiss() } else { failure = stretchCatalogText("ui.failed") }
                    }.disabled(!StretchCatalog.valid(entries))
                    .accessibilityIdentifier("StretchEditorSave")
                }
            }
            .sheet(isPresented: $picking) { picker }
            .overlay(alignment: .bottom) { if let failure { Text(failure).padding().background(.regularMaterial, in: Capsule()).padding() } }
            .task(id: failure) { if failure != nil { try? await Task.sleep(for: .seconds(3)); failure = nil } }
        }
    }
    private var picker: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                Picker(stretchCatalogText("ui.all"), selection: $area) {
                    ForEach(["all", "upper", "lower"], id: \.self) { Text(stretchCatalogText("ui." + $0)).tag($0) }
                }
                Picker(stretchCatalogText("ui.any"), selection: $requirement) {
                    ForEach(["any", "none", "wall", "floor", "surface"], id: \.self) { Text(stretchCatalogText("ui." + $0)).tag($0) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                ForEach(StretchCatalogData.definitions.filter { d in
                    (area == "all" || d.area == area) &&
                    (requirement == "any" || (requirement == "none" && !d.floor && !d.support && !d.surface) || (requirement == "wall" && d.support) || (requirement == "floor" && d.floor) || (requirement == "surface" && d.surface)) &&
                    (!entries.contains { $0.movementID == d.id } || d.id == replacing)
                }) { definition in
                    Button {
                        if let replacing, let index = entries.firstIndex(where: { $0.id == replacing }) {
                            entries[index].movementID = definition.id
                            onAction("replace")
                        } else {
                            entries.append(StretchEntry(movementID: definition.id, seconds: 25))
                            onAction("add")
                        }
                        picking = false
                    } label: {
                        VStack(spacing: 10) {
                            StretchPostureIllustration(cue: definition.id + (definition.bilateral ? "_left" : "_both")).frame(height: 120)
                            Text(definition.title).font(.subheadline.weight(.medium)).foregroundStyle(Color.primary)
                            Text(definition.requirements.isEmpty ? stretchCatalogText("ui.none") : definition.requirements).font(.caption).foregroundStyle(Color.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 190)
                        .padding(12).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                }
                }.padding(20)
            }
            .navigationTitle(stretchCatalogText(replacing == nil ? "ui.add" : "ui.replace"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(stretchCatalogText("ui.cancel")) { picking = false } } }
        }
    }
}
