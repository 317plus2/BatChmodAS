import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PermissionViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        content
            .padding(20)
            .frame(width: 508)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(dropHighlight)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
            .font(.system(size: 13))
            .alert(Text(L10n.string("alert.error.title")), isPresented: $model.isShowingError) {
                Button(L10n.string("button.ok"), role: .cancel) { }
            } message: {
                Text(model.errorMessage)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            targetPanel

            VStack(alignment: .leading, spacing: 6) {
                sectionHeading("label.permissions")
                permissionsPanel
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeading("label.settings")
                optionsPanel
            }

            recursionOptions
            actionBar
        }
    }

    private var targetPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isDirectory ? "folder" : "doc")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.path.isEmpty
                     ? L10n.string("status.chooseItem")
                     : URL(fileURLWithPath: model.path).lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.path)

                TextField(L10n.string("placeholder.path"), text: $model.path)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("label.path"))
                    .help(L10n.string("placeholder.path"))
                    .onSubmit { model.loadPath() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(L10n.string(model.hasSelection ? "button.change" : "button.file")) {
                model.chooseItem()
            }
            .buttonStyle(.bordered)
            .fixedSize()
        }
        .frame(minHeight: 48)
    }

    private func sectionHeading(_ key: String) -> some View {
        Text(L10n.string(key))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingToggle("toggle.changeOwnershipAndPermissions", isOn: $model.changeOwnershipAndPermissions)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                PermissionColumn(
                    title: L10n.string("label.owner"),
                    name: $model.ownerName,
                    options: model.availableUsers,
                    read: $model.ownerRead,
                    write: $model.ownerWrite,
                    execute: $model.ownerExecute,
                    showsNameField: true,
                    isEnabled: model.hasSelection && model.changeOwnershipAndPermissions,
                    onChange: model.updateOctalFromBits
                )

                PermissionColumn(
                    title: L10n.string("label.group"),
                    name: $model.groupName,
                    options: model.availableGroups,
                    read: $model.groupRead,
                    write: $model.groupWrite,
                    execute: $model.groupExecute,
                    showsNameField: true,
                    isEnabled: model.hasSelection && model.changeOwnershipAndPermissions,
                    onChange: model.updateOctalFromBits
                )

                PermissionColumn(
                    title: L10n.string("label.everyone"),
                    name: .constant(""),
                    options: [],
                    read: $model.otherRead,
                    write: $model.otherWrite,
                    execute: $model.otherExecute,
                    showsNameField: false,
                    isEnabled: model.hasSelection && model.changeOwnershipAndPermissions,
                    onChange: model.updateOctalFromBits
                )
            }
        }
        .padding(14)
        .settingsPanel()
    }

    private var optionsPanel: some View {
        VStack(spacing: 10) {
            settingToggle("toggle.clearACL", isOn: $model.clearACL)
            Divider()
            settingToggle("toggle.clearExtendedAttributes", isOn: $model.clearExtendedAttributes)
            Divider()
            settingToggle("toggle.unlock", isOn: $model.unlock)
        }
        .padding(14)
        .settingsPanel()
    }

    private var recursionOptions: some View {
        HStack(spacing: 24) {
            Toggle(L10n.string("toggle.applyRecursively"), isOn: $model.applyRecursively)
                .disabled(!model.isDirectory)

            Toggle(L10n.string("toggle.foldersOnly"), isOn: $model.foldersOnly)
                .disabled(!model.isDirectory || !model.applyRecursively)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(.horizontal, 4)
    }

    private func settingToggle(_ key: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(L10n.string(key))
            Spacer(minLength: 12)
            Toggle(L10n.string(key), isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
        }
        .frame(minHeight: 24)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Label(model.status, systemImage: model.statusIsError ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(model.statusIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .font(.system(size: 12))
                .lineLimit(1)
                .help(model.status)

            Spacer()

            Button {
                model.applyChanges()
            } label: {
                Label(L10n.string("button.apply"), systemImage: "checkmark")
                    .frame(width: 70)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canApply)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(2)
                .allowsHitTesting(false)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = droppedURL(from: item) else { return }
            Task { @MainActor in
                model.loadItem(at: url)
            }
        }
        return true
    }
}

private struct PermissionColumn: View {
    let title: String
    @Binding var name: String
    let options: [String]
    @Binding var read: Bool
    @Binding var write: Bool
    @Binding var execute: Bool
    let showsNameField: Bool
    let isEnabled: Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))

            if showsNameField {
                Picker(title, selection: $name) {
                    if !options.contains(name) {
                        Text(name).tag(name)
                    }
                    ForEach(options, id: \.self) { option in
                        Text(option)
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.regular)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .disabled(!isEnabled)
            } else {
                Color.clear
                    .frame(height: 24)
            }

            HStack(spacing: 12) {
                permissionToggle(L10n.string("permission.read"), isOn: $read)
                permissionToggle(L10n.string("permission.write"), isOn: $write)
                permissionToggle(L10n.string("permission.execute"), isOn: $execute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: read) { _, _ in onChange() }
        .onChange(of: write) { _, _ in onChange() }
        .onChange(of: execute) { _, _ in onChange() }
    }

    private func permissionToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))

            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!isEnabled)
        }
    }
}

private extension View {
    func settingsPanel() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            }
    }
}

private func droppedURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }

    if let data = item as? Data,
       let string = String(data: data, encoding: .utf8) {
        return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    if let string = item as? String {
        return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return nil
}
