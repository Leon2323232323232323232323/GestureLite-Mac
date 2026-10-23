import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection = 0
    private let triggers = (3...8).map { "Mouse\($0)" } + (13...20).map { "F\($0)" }
    private let presets = ["Copy": "CMD+C", "Paste": "CMD+V", "Save": "CMD+S", "Undo": "CMD+Z",
                           "Previous desktop": "CTRL+LEFT", "Next desktop": "CTRL+RIGHT", "Mission Control": "CTRL+UP"]

    private func action(_ path: WritableKeyPath<GestureBinding, String?>) -> Binding<String> {
        Binding(get: {
            guard model.draft.bindings.indices.contains(selection) else { return "" }
            return model.draft.bindings[selection][keyPath: path] ?? ""
        }, set: { value in
            guard model.draft.bindings.indices.contains(selection) else { return }
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            model.draft.bindings[selection][keyPath: path] = value.isEmpty ? nil : value
        })
    }
    private func actionRow(_ title: String, path: WritableKeyPath<GestureBinding, String?>) -> some View {
        HStack {
            Text(title).frame(width: 85, alignment: .leading)
            TextField("No action", text: action(path)).textFieldStyle(.roundedBorder)
            Menu("Preset") {
                Button("No action") { action(path).wrappedValue = "" }
                ForEach(presets.keys.sorted(), id: \.self) { name in
                    Button(name) { action(path).wrappedValue = presets[name] ?? "" }
                }
            }.frame(width: 85)
        }
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle("Enable gestures", isOn: Binding(get: { model.running }, set: { model.setEnabled($0) }))
                Spacer()
                Button("Request Permissions") { model.requestPermissions() }
            }
            Text("Hold a trigger and move for one gesture. Release without a gesture for the click action. No timer or repeat.")
                .font(.callout).foregroundColor(.secondary)
            HStack {
                Text("Distance")
                TextField("Points", value: $model.draft.distance, format: .number).frame(width: 75)
                Text("screen points (not physical pixels)").foregroundColor(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading) {
                    Text("Buttons / keys").font(.headline)
                    List(model.draft.bindings.indices, id: \.self) { index in
                        Button { selection = index } label: {
                            Text(model.draft.bindings[index].trigger)
                                .fontWeight(selection == index ? .bold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }.frame(width: 130, height: 245)
                    HStack {
                        Button("Add") {
                            if let name = triggers.first(where: { name in !model.draft.bindings.contains(where: { $0.trigger == name }) }) {
                                model.draft.bindings.append(.init(trigger: name, tapPassthrough: true))
                                selection = model.draft.bindings.count - 1
                            }
                        }.disabled(model.draft.bindings.count >= triggers.count)
                        Button("Remove") {
                            if model.draft.bindings.indices.contains(selection) {
                                model.draft.bindings.remove(at: selection)
                                selection = max(0, min(selection, model.draft.bindings.count - 1))
                            }
                        }.disabled(model.draft.bindings.isEmpty)
                    }
                }
                if model.draft.bindings.indices.contains(selection) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Trigger", selection: $model.draft.bindings[selection].trigger) {
                            let current = model.draft.bindings[selection].trigger
                            ForEach(triggers.contains(current) ? triggers : triggers + [current], id: \.self) { name in Text(name).tag(name) }
                        }
                        Toggle("Normal tap if no click action", isOn: $model.draft.bindings[selection].tapPassthrough)
                        actionRow("Click action", path: \.clickAction)
                        Divider()
                        actionRow("Left", path: \.left)
                        actionRow("Right", path: \.right)
                        actionRow("Up", path: \.up)
                        actionRow("Down", path: \.down)
                    }
                } else {
                    Text("Add a button or function-key trigger to configure actions.").frame(maxWidth: .infinity)
                }
            }
            Text("Mouse4/5 usually mean Back/Forward, but driver mappings vary. F13–F20 require a real held key-down/up pair. Shortcuts use Mac key positions; non-US layouts need testing.")
                .font(.caption).foregroundColor(.secondary)
            Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Open Configuration") { model.openConfiguration() }
                Spacer()
                Button("Save and Apply") { model.save() }.keyboardShortcut("s", modifiers: .command)
            }
        }.padding(20)
        }.frame(width: 710, height: 640)
    }
}
