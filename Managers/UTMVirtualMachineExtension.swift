//
// Copyright © 2020 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

extension UTMVirtualMachine: Identifiable {
    public var id: String {
        if self.bookmark != nil {
            return bookmark!.base64EncodedString()
        } else {
            return self.path.path // path if we're an existing VM
        }
    }
}

extension UTMVirtualMachine: ObservableObject {
    
}

@objc extension UTMVirtualMachine {
    fileprivate static let gibInMib = 1024
    func subscribeToChildren() -> [AnyObject] {
        var s: [AnyObject] = []
        if let config = config.qemuConfig {
            s.append(config.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            })
        } else if let config = config.appleConfig {
            s.append(config.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            })
        }
        s.append(registryEntry.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
        return s
    }
    
    @MainActor func propertyWillChange() -> Void {
        objectWillChange.send()
    }
    
    @nonobjc convenience init<Config: UTMConfiguration>(newConfig: Config, destinationURL: URL) {
        let packageURL = UTMVirtualMachine.virtualMachinePath(newConfig.information.name, inParentURL: destinationURL)
        let configuration = UTMConfigurationWrapper(wrapping: newConfig)
        self.init(configuration: configuration, packageURL: packageURL)
    }
}

@objc extension UTMVirtualMachine {
    func reloadConfiguration() throws {
        try config.reload(from: path)
    }
    
    func saveUTM() async throws {
        let fileManager = FileManager.default
        let existingPath = path
        let newPath = existingPath.deletingLastPathComponent().appendingPathComponent(config.name).appendingPathExtension("utm")
        do {
            try await config.save(to: existingPath)
            try await updateRegistryPostSave()
        } catch {
            try? reloadConfiguration()
            throw error
        }
        if existingPath.path != newPath.path {
            try await Task.detached {
                try fileManager.moveItem(at: existingPath, to: newPath)
            }.value
            path = newPath
            try reloadConfiguration()
        }
    }
    
    @MainActor func updateRegistryPostSave() async throws {
        registryEntry.name = config.name
        let oldRemoteBookmark = registryEntry.package.remoteBookmark
        registryEntry.package = try UTMRegistryEntry.File(url: path)
        registryEntry.package.remoteBookmark = oldRemoteBookmark
    }
}

public extension UTMQemuVirtualMachine {
    @MainActor override var detailsTitleLabel: String {
        config.qemuConfig!.information.name
    }
    
    @MainActor override var detailsSubtitleLabel: String {
        self.detailsSystemTargetLabel
    }
    
    @MainActor override var detailsNotes: String? {
        config.qemuConfig!.information.notes
    }
    
    @MainActor override var detailsSystemTargetLabel: String {
        config.qemuConfig!.system.target.prettyValue
    }
    
    @MainActor override var detailsSystemArchitectureLabel: String {
        config.qemuConfig!.system.architecture.prettyValue
    }
    
    @MainActor override var detailsSystemMemoryLabel: String {
        let bytesInMib = Int64(1048576)
        return ByteCountFormatter.string(fromByteCount: Int64(config.qemuConfig!.system.memorySize) * bytesInMib, countStyle: .memory)
    }
    
    /// Check if a QEMU target is supported
    /// - Parameter systemArchitecture: QEMU architecture
    /// - Returns: true if UTM is compiled with the supporting binaries
    internal static func isSupported(systemArchitecture: QEMUArchitecture) -> Bool {
        let arch = systemArchitecture.rawValue
        let bundleURL = Bundle.main.bundleURL
        #if os(macOS)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let base = "Versions/A/"
        #else
        let contentsURL = bundleURL
        let base = ""
        #endif
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        let framework = frameworksURL.appendingPathComponent("qemu-" + arch + "-softmmu.framework/" + base + "qemu-" + arch + "-softmmu", isDirectory: false)
        logger.error("\(framework.path)")
        return FileManager.default.fileExists(atPath: framework.path)
    }
    
    /// Check if the current VM target is supported by the host
    @objc var isSupported: Bool {
        return UTMQemuVirtualMachine.isSupported(systemArchitecture: config.qemuConfig!._system.architecture)
    }
}

// MARK: - Bookmark handling
extension URL {
    private static var defaultCreationOptions: BookmarkCreationOptions {
        #if os(iOS)
        return .minimalBookmark
        #else
        return .withSecurityScope
        #endif
    }
    
    private static var defaultResolutionOptions: BookmarkResolutionOptions {
        #if os(iOS)
        return []
        #else
        return .withSecurityScope
        #endif
    }
    
    func persistentBookmarkData(isReadyOnly: Bool = false) throws -> Data {
        var options = Self.defaultCreationOptions
        #if os(macOS)
        if isReadyOnly {
            options.insert(.securityScopeAllowOnlyReadAccess)
        }
        #endif
        return try self.bookmarkData(options: options,
                                     includingResourceValuesForKeys: nil,
                                     relativeTo: nil)
    }
    
    init(resolvingPersistentBookmarkData bookmark: Data) throws {
        var stale: Bool = false
        try self.init(resolvingBookmarkData: bookmark,
                      options: Self.defaultResolutionOptions,
                      bookmarkDataIsStale: &stale)
    }
}
