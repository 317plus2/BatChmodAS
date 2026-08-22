import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = PermissionViewModel()
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 16) {
                    content
                }
            } else {
                content
            }
        }
        .padding(20)
        .frame(width: 560, height: 500)
        .background(ambientBackground)
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
        VStack(spacing: 16) {
            targetPanel
            permissionsPanel
            optionsPanel
            actionBar
        }
    }

    private var targetPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 34)

            TextField(L10n.string("status.chooseItem"), text: $model.path)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit { model.loadPath() }

            Button {
                model.chooseItem()
            } label: {
                Label(L10n.string("button.file"), systemImage: "folder.badge.plus")
            }
            .adaptiveGlassButton()
            .controlSize(.large)
        }
        .padding(16)
        .adaptiveGlassPanel()
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $model.changeOwnershipAndPermissions) {
                Label(
                    L10n.string("toggle.changeOwnershipAndPermissions"),
                    systemImage: "person.2.badge.gearshape"
                )
                .font(.headline)
            }
            .toggleStyle(.switch)

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
                    isEnabled: model.hasSelection,
                    onChange: model.updateOctalFromBits
                )

                Divider()

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

                Divider()

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
            }
            .disabled(!model.changeOwnershipAndPermissions)
        }
        .padding(18)
        .adaptiveGlassPanel()
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.string("label.settings"), systemImage: "slider.horizontal.3")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow {
                    Toggle(isOn: $model.clearACL) {
                        Label(L10n.string("toggle.clearACL"), systemImage: "list.bullet.rectangle")
                    }

                    Toggle(isOn: $model.unlock) {
                        Label(L10n.string("toggle.unlock"), systemImage: "lock.open")
                    }
                }

                GridRow {
                    Toggle(isOn: $model.clearExtendedAttributes) {
                        Label(L10n.string("toggle.clearExtendedAttributes"), systemImage: "tag.slash")
                    }

                    Color.clear
                }
            }
            .toggleStyle(.switch)

            Divider()

            HStack(spacing: 24) {
                Toggle(isOn: $model.applyRecursively) {
                    Label(L10n.string("toggle.applyRecursively"), systemImage: "arrow.triangle.branch")
                }
                .disabled(!model.isDirectory)

                Toggle(isOn: $model.foldersOnly) {
                    Text(L10n.string("toggle.foldersOnly"))
                }
                .disabled(!model.isDirectory || !model.applyRecursively)
            }
            .toggleStyle(.checkbox)
        }
        .padding(18)
        .adaptiveGlassPanel()
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Label(model.status, systemImage: model.statusIsError ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(model.statusIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .lineLimit(1)

            Spacer()

            Button {
                model.applyChanges()
            } label: {
                Label(L10n.string("button.apply"), systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .adaptiveGlassButton(prominent: true)
            .controlSize(.large)
            .disabled(!model.canApply)
        }
        .padding(.horizontal, 4)
    }

    private var ambientBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    Color.clear,
                    Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if showsNameField {
                Picker("", selection: $name) {
                    ForEach(options, id: \.self) { option in
                        Text(option)
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.regular)
                .labelsHidden()
            } else {
                Color.clear
                    .frame(height: 24)
            }

            HStack(spacing: 14) {
                permissionToggle(L10n.string("permission.read"), isOn: $read)
                permissionToggle(L10n.string("permission.write"), isOn: $write)
                permissionToggle(L10n.string("permission.execute"), isOn: $execute)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: read) { _, _ in onChange() }
        .onChange(of: write) { _, _ in onChange() }
        .onChange(of: execute) { _, _ in onChange() }
        .disabled(!isEnabled)
    }

    private func permissionToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
        }
    }
}

private extension View {
    func adaptiveGlassPanel() -> some View {
        modifier(AdaptiveGlassPanelModifier())
    }

    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        modifier(AdaptiveGlassButtonModifier(prominent: prominent))
    }
}

private struct AdaptiveGlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.separator.opacity(colorScheme == .dark ? 0.55 : 0.35), lineWidth: 0.5)
                }
        }
    }
}

private struct AdaptiveGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
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
