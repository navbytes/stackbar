#if canImport(SwiftUI)
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif
import SwiftUI
import StackbarProtocol

/// A form: its fields keep drafts, and the submit button (or Return in a
/// one-line field, or ⌘Return anywhere) sends every value at once as
/// `.fields`. The plugin answers with the same form again, with an `error`
/// on any field it rejected; drafts survive that re-render.
struct FormNodeView: View {
    let form: FormNode
    let send: SendAction
    @State private var values: [String: EventValue] = [:]
    @FocusState private var focused: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(form.fields, id: \.name) { field in
                VStack(alignment: .leading, spacing: 3) {
                    fieldView(field)
                    if let error = field.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            HStack {
                Spacer()
                Button(form.submitTitle) { submit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            seed()
            focused = form.fields.first { if case .toggle = $0.kind { return false } else { return true } }?.name
        }
        .onChange(of: form.fields.map(\.name)) { _, _ in seed() }
    }

    @ViewBuilder private func fieldView(_ field: FormField) -> some View {
        switch field.kind {
        case .text(let placeholder):
            LabeledContent(field.label) {
                TextField(placeholder ?? "", text: text(field.name))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: field.name)
                    .onSubmit { submit() }
            }
        case .multiline(let placeholder):
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: text(field.name))
                        .font(.body)
                        .focused($focused, equals: field.name)
                        .frame(minHeight: 80, maxHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    if let placeholder, (values[field.name]?.textValue ?? "").isEmpty {
                        Text(placeholder).foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                    }
                }
            }
        case .application:
            LabeledContent(field.label) {
                ApplicationPicker(bundleID: text(field.name))
            }
        case .picker(let options):
            Picker(field.label, selection: text(field.name)) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .toggle:
            Toggle(field.label, isOn: Binding(
                get: { if case .bool(let isOn)? = values[field.name] { return isOn } else { return false } },
                set: { values[field.name] = .bool($0) }
            ))
        }
    }

    private func text(_ name: String) -> Binding<String> {
        Binding(get: { values[name]?.textValue ?? "" }, set: { values[name] = .text($0) })
    }

    /// Starting values for fields not yet edited (a re-render keeps drafts).
    private func seed() {
        for field in form.fields where values[field.name] == nil {
            switch field.kind {
            case .toggle:
                values[field.name] = field.value ?? .bool(false)
            case .picker(let options):
                values[field.name] = field.value ?? options.first.map(EventValue.text) ?? .text("")
            case .text, .multiline, .application:
                values[field.name] = field.value ?? .text("")
            }
        }
        let names = Set(form.fields.map(\.name))
        values = values.filter { names.contains($0.key) }
    }

    private func submit() {
        seed()
        send(form.action, .fields(values))
    }
}

extension EventValue {
    var textValue: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}

/// Picks an installed app; the value is its bundle id. Lists the apps in the
/// standard Applications folders, plus "Other…" for anything elsewhere.
struct ApplicationPicker: View {
    @Binding var bundleID: String
    @State private var apps: [InstalledApp] = InstalledApp.cached ?? []

    var body: some View {
        Menu {
            Button("None") { bundleID = "" }
            Divider()
            ForEach(apps) { app in
                Button {
                    bundleID = app.id
                } label: {
                    #if canImport(AppKit)
                    Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                    #else
                    Text(app.name)
                    #endif
                }
            }
            #if canImport(AppKit)
            Divider()
            Button("Other…") { chooseOther() }
            #endif
        } label: {
            Text(apps.first { $0.id == bundleID }?.name ?? (bundleID.isEmpty ? "Choose an app" : bundleID))
        }
        .fixedSize()
        .task {
            if apps.isEmpty { apps = await InstalledApp.load() }
        }
    }

    #if canImport(AppKit)
    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if !apps.contains(where: { $0.id == id }) {
            apps.append(InstalledApp(url: url, id: id))
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        bundleID = id
    }
    #endif
}

/// An app found in an Applications folder.
public struct InstalledApp: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let url: URL

    init(url: URL, id: String) {
        self.url = url
        self.id = id
        let bundle = Bundle(url: url)
        name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    #if canImport(AppKit)
    @MainActor var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
    #endif

    @MainActor static var cached: [InstalledApp]?

    /// Every app in /Applications, /System/Applications and
    /// ~/Applications (one level of subfolders), by name, once per launch.
    @MainActor public static func load() async -> [InstalledApp] {
        if let cached { return cached }
        let found = await Task.detached { scan() }.value
        cached = found
        return found
    }

    static func scan() -> [InstalledApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", home.appendingPathComponent("Applications").path]
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        func visit(_ folder: URL, depth: Int) {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    guard let id = Bundle(url: item)?.bundleIdentifier, seen.insert(id).inserted else { continue }
                    apps.append(InstalledApp(url: item, id: id))
                } else if depth > 0, (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    visit(item, depth: depth - 1)
                }
            }
        }
        for root in roots { visit(URL(fileURLWithPath: root), depth: 1) }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
#endif
