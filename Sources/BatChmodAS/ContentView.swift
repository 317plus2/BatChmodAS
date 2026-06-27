import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = PermissionViewModel()
    @State private var changeOwnershipAndPermissions = false
    @State private var clearACL = false
    @State private var unlock = false
    @State private var clearExtendedAttributes = false
    @State private var foldersOnly = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            fileRow
            permissionsArea
            optionsArea
            recursionArea
            bottomButtons
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .frame(width: 397, height: 276, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(dropHighlight)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
        .font(.system(size: 11))
        .alert(Text(L10n.string("alert.error.title")), isPresented: $model.isShowingError) {
            Button(L10n.string("button.ok"), role: .cancel) { }
        } message: {
            Text(model.errorMessage)
        }
    }

    private var fileRow: some View {
        HStack(spacing: 7) {
            Button {
                model.chooseItem()
            } label: {
                Text(L10n.string("button.file"))
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 63)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            TextField("", text: $model.path)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11))
                .frame(height: 20)
                .onSubmit { model.loadPath() }
        }
    }

    private var permissionsArea: some View {
        HStack(alignment: .top, spacing: 26) {
            PermissionColumn(
                title: L10n.string("label.owner"),
                name: $model.ownerName,
                options: model.availableUsers,
                read: $model.ownerRead,
                write: $model.ownerWrite,
                execute: $model.ownerExecute,
                showsNameField: true,
                isEnabled: model.hasSelection,
                onChange: model.updateOctalFromBits
            )
            .frame(width: 92, alignment: .leading)

            PermissionColumn(
                title: L10n.string("label.group"),
                name: $model.groupName,
                options: model.availableGroups,
                read: $model.groupRead,
                write: $model.groupWrite,
                execute: $model.groupExecute,
                showsNameField: true,
                isEnabled: model.hasSelection,
                onChange: model.updateOctalFromBits
            )
            .frame(width: 92, alignment: .leading)

            PermissionColumn(
                title: L10n.string("label.everyone"),
                name: .constant(""),
                options: [],
                read: $model.otherRead,
                write: $model.otherWrite,
                execute: $model.otherExecute,
                showsNameField: false,
                isEnabled: model.hasSelection,
                onChange: model.updateOctalFromBits
            )
            .frame(width: 118, alignment: .leading)
        }
        .padding(.top, 2)
        .padding(.leading, 8)
    }

    private var optionsArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string("label.settings"))
                .font(.system(size: 10))
                .padding(.leading, 7)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: $changeOwnershipAndPermissions) {
                        Text(L10n.string("toggle.changeOwnershipAndPermissions"))
                    }
                    Toggle(isOn: $clearACL) {
                        Text(L10n.string("toggle.clearACL"))
                    }
                }
                .frame(width: 198, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: $unlock) {
                        Text(L10n.string("toggle.unlock"))
                    }
                    Toggle(isOn: $clearExtendedAttributes) {
                        Text(L10n.string("toggle.clearExtendedAttributes"))
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(true)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(width: 358, height: 40, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
                    )
            }
        }
        .padding(.leading, 10)
    }

    private var recursionArea: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: $model.applyRecursively) {
                Text(L10n.string("toggle.applyRecursively"))
            }
                .toggleStyle(.checkbox)
                .disabled(!model.isDirectory)

            Toggle(isOn: $foldersOnly) {
                Text(L10n.string("toggle.foldersOnly"))
            }
                .toggleStyle(.checkbox)
                .disabled(true)
                .padding(.leading, 46)
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 18)
        .padding(.top, 1)
    }

    private var bottomButtons: some View {
        HStack {
            Spacer()

            Button(L10n.string("button.export")) { }
                .controlSize(.small)
                .frame(width: 92)
                .disabled(true)

            Button(L10n.string("button.apply")) {
                model.applyChanges()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.small)
            .frame(width: 70)
            .disabled(!model.canApply)
        }
        .padding(.top, -3)
        .padding(.trailing, 14)
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
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11))

            if showsNameField {
                Picker("", selection: $name) {
                    ForEach(options, id: \.self) { option in
                        Text(option)
                            .tag(option)
                    }
                }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 84, height: 19)
                    .labelsHidden()
            } else {
                Color.clear
                    .frame(width: 84, height: 19)
            }

            HStack(spacing: 10) {
                Text(L10n.string("permission.read"))
                Text(L10n.string("permission.write"))
                Text(L10n.string("permission.execute"))
            }
            .font(.system(size: 11, weight: .bold))

            HStack(spacing: 17) {
                Toggle("", isOn: $read)
                Toggle("", isOn: $write)
                Toggle("", isOn: $execute)
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
        }
        .onChange(of: read) { _, _ in onChange() }
        .onChange(of: write) { _, _ in onChange() }
        .onChange(of: execute) { _, _ in onChange() }
        .disabled(!isEnabled)
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
