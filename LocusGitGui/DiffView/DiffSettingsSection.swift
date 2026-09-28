import SwiftUI

/// How every diff looks, and the options a repository starts with.
struct DiffSettingsSection: View {
    @Bindable var store: DiffSettingsStore

    private static let fontSizes: [Double] = [9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24]

    var body: some View {
        Section {
            Picker(selection: $store.layout) {
                Text("Side by side when there’s room").tag(DiffPreferences.Layout.automatic)
                Text("Always side by side").tag(DiffPreferences.Layout.sideBySide)
                Text("Always inline").tag(DiffPreferences.Layout.inline)
            } label: {
                Text("Layout")
                Text("Added and deleted files are always inline, since one side would be empty.")
            }
        }

        Section {
            Picker("Font", selection: $store.fontFamily) {
                Text("System Font").tag(String?.none)
                Divider()
                ForEach(store.fixedWidthFamilies, id: \.self) { family in
                    Text(family).tag(Optional(family))
                }
            }
            Picker("Size", selection: $store.fontSize) {
                ForEach(Self.fontSizes, id: \.self) { size in
                    Text("\(Int(size)) pt").tag(size)
                }
            }
            preview
        } footer: {
            Text("Also used for the versions of a file in the conflict window.")
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("Ignore whitespace", isOn: $store.defaultOptions.ignoresWhitespace)
            Picker("Context lines", selection: $store.defaultOptions.contextLines) {
                ForEach(DiffOptions.contextSteps, id: \.self) { lines in
                    Text(lines == DiffOptions().contextLines ? "\(lines) (Git’s default)" : "\(lines)").tag(lines)
                }
            }
        } header: {
            Text("Defaults for Every Repository")
        } footer: {
            Text("""
            A repository follows these until you change them for it in the View menu. Changing one \
            back to match these defaults makes it follow them again.
            """)
            .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        Text(verbatim: "func greet(_ name: String) -> String {\n    return \"Hello, \\(name)!\"\n}")
            .font(Font(store.font))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .accessibilityLabel("Preview of the diff font")
    }
}
