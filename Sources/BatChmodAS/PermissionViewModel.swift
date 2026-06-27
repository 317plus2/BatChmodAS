import AppKit
import Foundation
import Darwin

@MainActor
final class PermissionViewModel: ObservableObject {
    @Published var path = ""
    @Published var ownerName = ""
    @Published var groupName = ""
    @Published var octalMode = "000"
    @Published var applyRecursively = false

    @Published var ownerRead = false
    @Published var ownerWrite = false
    @Published var ownerExecute = false
    @Published var groupRead = false
    @Published var groupWrite = false
    @Published var groupExecute = false
    @Published var otherRead = false
    @Published var otherWrite = false
    @Published var otherExecute = false

    @Published var status = L10n.string("status.chooseItem")
    @Published var statusIsError = false
    @Published var errorMessage = ""
    @Published var isShowingError = false
    @Published private(set) var availableUsers = [String]()
    @Published private(set) var availableGroups = [String]()

    private var currentUID: uid_t = getuid()
    private var currentGID: gid_t = getgid()
    private var currentMode: mode_t = 0o755
    private var isUpdatingBits = false
    private var selectedURL: URL?

    init() {
        reloadAccounts()
    }

    var isDirectory: Bool {
        guard let selectedURL else { return false }
        var isDir = ObjCBool(false)
        FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    var hasSelection: Bool {
        selectedURL != nil
    }

    var itemSummary: String? {
        guard selectedURL != nil else { return nil }
        let kind = isDirectory ? "フォルダ" : "ファイル"
        return "\(kind) / \(ownerName):\(groupName) / \(octalMode)"
    }

    var canApply: Bool {
        !path.isEmpty && UInt16(octalMode, radix: 8) != nil
    }

    func chooseItem() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.string("button.choose")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedURL = url
        path = url.path
        loadPath()
    }

    func loadItem(at url: URL) {
        selectedURL = url
        path = url.path
        loadPath()
    }

    func loadPath() {
        guard !path.isEmpty else { return }
        selectedURL = URL(fileURLWithPath: path)

        var info = stat()
        guard lstat(path, &info) == 0 else {
            showError(L10n.format("error.cannotReadInfo", posixErrorMessage()))
            return
        }

        currentUID = info.st_uid
        currentGID = info.st_gid
        currentMode = info.st_mode & 0o7777
        ownerName = nameForUser(id: currentUID) ?? String(currentUID)
        groupName = nameForGroup(id: currentGID) ?? String(currentGID)
        includeCurrentAccountNames()
        setMode(currentMode)
        setStatus(L10n.string("status.loaded"), isError: false)
    }

    func reloadAccounts() {
        availableUsers = accountUsers()
        availableGroups = accountGroups()
        includeCurrentAccountNames()
    }

    func updateBitsFromOctal(_ value: String) {
        guard !isUpdatingBits, let mode = UInt16(value, radix: 8), mode <= 0o7777 else { return }
        setMode(mode_t(mode))
    }

    func updateOctalFromBits() {
        guard !isUpdatingBits else { return }
        var mode: mode_t = 0
        if ownerRead { mode |= S_IRUSR }
        if ownerWrite { mode |= S_IWUSR }
        if ownerExecute { mode |= S_IXUSR }
        if groupRead { mode |= S_IRGRP }
        if groupWrite { mode |= S_IWGRP }
        if groupExecute { mode |= S_IXGRP }
        if otherRead { mode |= S_IROTH }
        if otherWrite { mode |= S_IWOTH }
        if otherExecute { mode |= S_IXOTH }
        currentMode = mode
        octalMode = String(format: "%03o", mode)
    }

    func applyChanges() {
        guard let url = selectedURL else {
            showError(L10n.string("status.chooseItem"))
            return
        }
        guard let parsedMode = UInt16(octalMode, radix: 8), parsedMode <= 0o7777 else {
            showError(L10n.string("error.invalidOctalMode"))
            return
        }

        let targetPath = url.path
        let desiredMode = mode_t(parsedMode)
        let desiredUID = idForUser(name: ownerName)
        let desiredGID = idForGroup(name: groupName)

        guard desiredUID != nil || ownerName == String(currentUID) || ownerName == nameForUser(id: currentUID) else {
            showError(L10n.format("error.userNotFound", ownerName))
            return
        }
        guard desiredGID != nil || groupName == String(currentGID) || groupName == nameForGroup(id: currentGID) else {
            showError(L10n.format("error.groupNotFound", groupName))
            return
        }

        do {
            try applyMode(desiredMode, to: targetPath)
            try applyOwnerIfNeeded(uid: desiredUID ?? currentUID, gid: desiredGID ?? currentGID, to: targetPath)
            loadPath()
            setStatus(L10n.string("status.applied"), isError: false)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func setMode(_ mode: mode_t) {
        isUpdatingBits = true
        currentMode = mode
        octalMode = String(format: "%03o", mode & 0o7777)
        ownerRead = mode & S_IRUSR != 0
        ownerWrite = mode & S_IWUSR != 0
        ownerExecute = mode & S_IXUSR != 0
        groupRead = mode & S_IRGRP != 0
        groupWrite = mode & S_IWGRP != 0
        groupExecute = mode & S_IXGRP != 0
        otherRead = mode & S_IROTH != 0
        otherWrite = mode & S_IWOTH != 0
        otherExecute = mode & S_IXOTH != 0
        isUpdatingBits = false
    }

    private func applyMode(_ mode: mode_t, to targetPath: String) throws {
        if applyRecursively && isDirectory {
            try runTool("/bin/chmod", arguments: ["-R", String(format: "%03o", mode), targetPath], useAdmin: false)
            return
        }

        if chmod(targetPath, mode) == 0 {
            return
        }

        if errno == EPERM || errno == EACCES {
            try runTool("/bin/chmod", arguments: [String(format: "%03o", mode), targetPath], useAdmin: true)
            return
        }

        throw PermissionError.operationFailed(L10n.format("error.chmodFailed", posixErrorMessage()))
    }

    private func applyOwnerIfNeeded(uid: uid_t, gid: gid_t, to targetPath: String) throws {
        guard uid != currentUID || gid != currentGID else { return }

        let ownerGroup = "\(nameForUser(id: uid) ?? String(uid)):\(nameForGroup(id: gid) ?? String(gid))"
        var arguments = [String]()
        if applyRecursively && isDirectory {
            arguments.append("-R")
        }
        arguments.append(ownerGroup)
        arguments.append(targetPath)

        try runTool("/usr/sbin/chown", arguments: arguments, useAdmin: true)
    }

    private func runTool(_ launchPath: String, arguments: [String], useAdmin: Bool) throws {
        if useAdmin {
            let command = ([launchPath] + arguments).map(shellQuote).joined(separator: " ")
            try runAppleScriptAdmin(command)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PermissionError.operationFailed(message?.isEmpty == false ? message! : L10n.format("error.toolFailed", launchPath))
        }
    }

    private func runAppleScriptAdmin(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(appleScriptString(command)) with administrator privileges"]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PermissionError.operationFailed(message?.isEmpty == false ? message! : L10n.string("error.adminFailed"))
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        status = message
        statusIsError = isError
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
        setStatus(message, isError: true)
    }

    private func includeCurrentAccountNames() {
        appendIfMissing(ownerName, to: &availableUsers)
        appendIfMissing(groupName, to: &availableGroups)
    }
}

private enum PermissionError: LocalizedError {
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .operationFailed(let message):
            return message
        }
    }
}

private func nameForUser(id: uid_t) -> String? {
    guard let entry = getpwuid(id), let name = entry.pointee.pw_name else { return nil }
    return String(cString: name)
}

private func nameForGroup(id: gid_t) -> String? {
    guard let entry = getgrgid(id), let name = entry.pointee.gr_name else { return nil }
    return String(cString: name)
}

private func idForUser(name: String) -> uid_t? {
    if let numeric = uid_t(name) {
        return numeric
    }
    guard let entry = getpwnam(name) else { return nil }
    return entry.pointee.pw_uid
}

private func idForGroup(name: String) -> gid_t? {
    if let numeric = gid_t(name) {
        return numeric
    }
    guard let entry = getgrnam(name) else { return nil }
    return entry.pointee.gr_gid
}

private func accountUsers() -> [String] {
    setpwent()
    defer { endpwent() }

    var names = Set<String>()
    while let entry = getpwent(), let name = entry.pointee.pw_name {
        names.insert(String(cString: name))
    }
    return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

private func accountGroups() -> [String] {
    setgrent()
    defer { endgrent() }

    var names = Set<String>()
    while let entry = getgrent(), let name = entry.pointee.gr_name {
        names.insert(String(cString: name))
    }
    return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

private func appendIfMissing(_ value: String, to values: inout [String]) {
    guard !value.isEmpty, !values.contains(value) else { return }
    values.append(value)
    values.sort { $0.localizedStandardCompare($1) == .orderedAscending }
}

private func posixErrorMessage() -> String {
    String(cString: strerror(errno))
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func appleScriptString(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
