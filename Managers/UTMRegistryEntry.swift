//
// Copyright © 2022 osy. All rights reserved.
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

@objc class UTMRegistryEntry: NSObject, Codable, ObservableObject {
    @Published private var _name: String
    
    @Published private var _package: File
    
    var uuid: UUID
    
    @Published private var _isSuspended: Bool
    
    @Published private var _externalDrives: [String: File]
    
    @Published private var _sharedDirectories: [File]
    
    @Published private var _windowSettings: [Int: Window]
    
    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case package = "Package"
        case uuid = "UUID"
        case isSuspended = "Suspended"
        case externalDrives = "ExternalDrives"
        case sharedDirectories = "SharedDirectories"
        case windowSettings = "WindowSettings"
    }
    
    init?(newFrom vm: UTMVirtualMachine) {
        guard let bookmark = vm.bookmark else {
            return nil
        }
        let path = vm.path.path
        _name = vm.detailsTitleLabel
        guard let package = try? File(path: path, bookmark: bookmark, isReadOnly: false) else {
            return nil
        }
        _package = package;
        uuid = vm.config.uuid
        _isSuspended = false
        _externalDrives = [:]
        _sharedDirectories = []
        _windowSettings = [:]
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _name = try container.decode(String.self, forKey: .name)
        _package = try container.decode(File.self, forKey: .package)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        _isSuspended = try container.decode(Bool.self, forKey: .isSuspended)
        _externalDrives = try container.decode([String: File].self, forKey: .externalDrives)
        _sharedDirectories = try container.decode([File].self, forKey: .sharedDirectories)
        _windowSettings = try container.decode([Int: Window].self, forKey: .windowSettings)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_name, forKey: .name)
        try container.encode(_package, forKey: .package)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(_isSuspended, forKey: .isSuspended)
        try container.encode(_externalDrives, forKey: .externalDrives)
        try container.encode(_sharedDirectories, forKey: .sharedDirectories)
        try container.encode(_windowSettings, forKey: .windowSettings)
    }
    
    func asDictionary() throws -> [String: Any] {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let xml = try encoder.encode(self)
        let dict = try PropertyListSerialization.propertyList(from: xml, format: nil)
        return dict as! [String: Any]
    }
}

protocol UTMRegistryEntryDecodable: Decodable {}
extension UTMRegistryEntry: UTMRegistryEntryDecodable {}
extension UTMRegistryEntryDecodable {
    init(from dictionary: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let decoder = PropertyListDecoder()
        self = try decoder.decode(Self.self, from: data)
    }
}

// MARK: - Accessors
@MainActor extension UTMRegistryEntry {
    var name: String {
        get {
            _name
        }
        
        set {
            _name = newValue
        }
    }
    
    var package: File {
        get {
            _package
        }
        
        set {
            _package = newValue
        }
    }
    
    var isSuspended: Bool {
        get {
            _isSuspended
        }
        
        set {
            _isSuspended = newValue
        }
    }
    
    var externalDrives: [String: File] {
        get {
            _externalDrives
        }
        
        set {
            _externalDrives = newValue
        }
    }
    
    var sharedDirectories: [File] {
        get {
            _sharedDirectories
        }
        
        set {
            _sharedDirectories = newValue
        }
    }
    
    var windowSettings: [Int: Window] {
        get {
            _windowSettings
        }
        
        set {
            _windowSettings = newValue
        }
    }
    
    func setExternalDrive(_ file: File, forId id: String) {
        externalDrives[id] = file
    }
    
    func updateExternalDriveRemoteBookmark(_ bookmark: Data, forId id: String) {
        externalDrives[id]?.remoteBookmark = bookmark
    }
    
    func removeExternalDrive(forId id: String) {
        externalDrives.removeValue(forKey: id)
    }
    
    func setSingleSharedDirectory(_ file: File) {
        sharedDirectories = [file]
    }
    
    func updateSingleSharedDirectoryRemoteBookmark(_ bookmark: Data) {
        if !sharedDirectories.isEmpty {
            sharedDirectories[0].remoteBookmark = bookmark
        }
    }
    
    func removeAllSharedDirectories() {
        sharedDirectories = []
    }
}

// MARK: - Migration from UTMViewState

extension UTMRegistryEntry {
    /// Migrate from a view state
    /// - Parameter viewState: View state to migrate
    private func migrate(viewState: UTMLegacyViewState) {
        var primaryWindow = Window()
        if viewState.displayScale != .zero {
            primaryWindow.scale = viewState.displayScale
        }
        if viewState.displayOriginX != .zero || viewState.displayOriginY != .zero {
            primaryWindow.origin = CGPoint(x: viewState.displayOriginX,
                                           y: viewState.displayOriginY)
        }
        primaryWindow.isKeyboardVisible = viewState.isKeyboardShown
        primaryWindow.isToolbarVisible = viewState.isToolbarShown
        if primaryWindow != Window() {
            _windowSettings[0] = primaryWindow
        }
        _isSuspended = viewState.hasSaveState
        if let sharedDirectoryBookmark = viewState.sharedDirectory, let sharedDirectoryPath = viewState.sharedDirectoryPath {
            if let file = try? File(path: sharedDirectoryPath,
                                    bookmark: sharedDirectoryBookmark) {
                _sharedDirectories = [file]
            } else {
                logger.error("Failed to migrate shared directory \(sharedDirectoryPath) because bookmark is invalid.")
            }
        }
        if let shortcutBookmark = viewState.shortcutBookmark {
            _package.remoteBookmark = shortcutBookmark
        }
        for drive in viewState.allDrives() {
            if let bookmark = viewState.bookmark(forRemovableDrive: drive), let path = viewState.path(forRemovableDrive: drive) {
                let file = File(path: path, remoteBookmark: bookmark)
                _externalDrives[drive] = file
            }
        }
    }
    
    /// Try to migrate from a view.plist or does nothing if it does not exist.
    /// - Parameter viewStateURL: URL to view.plist
    @objc func migrateUnsafe(viewStateURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: viewStateURL.path) else {
            return
        }
        guard let dict = try? NSDictionary(contentsOf: viewStateURL, error: ()) as? [AnyHashable : Any] else {
            logger.error("Failed to parse legacy \(viewStateURL)")
            return
        }
        let viewState = UTMLegacyViewState(dictionary: dict)
        migrate(viewState: viewState)
        try? fileManager.removeItem(at: viewStateURL) // delete view.plist
    }
}

// MARK: - Objective C bridging
// FIXME: these are NOT synchronized to the actor
@objc extension UTMRegistryEntry {
    var hasSaveState: Bool {
        get {
            _isSuspended
        }
        
        set {
            _isSuspended = newValue
        }
    }
    
    var packageRemoteBookmark: Data? {
        get {
            _package.remoteBookmark
        }
        
        set {
            _package.remoteBookmark = newValue
        }
    }
    
    var packageRemotePath: String? {
        get {
            if _package.remoteBookmark != nil {
                return _package.path
            } else {
                return nil
            }
        }
        
        set {
            if newValue != nil {
                _package.path = newValue!
            }
        }
    }
}

extension UTMRegistryEntry {
    struct File: Codable {
        var url: URL
        
        var path: String
        
        var bookmark: Data
        
        var remoteBookmark: Data?
        
        var isReadOnly: Bool
        
        private enum CodingKeys: String, CodingKey {
            case path = "Path"
            case bookmark = "Bookmark"
            case remoteBookmark = "BookmarkRemote"
            case isReadOnly = "ReadOnly"
        }
        
        init(path: String, bookmark: Data, isReadOnly: Bool = false) throws {
            self.path = path
            self.bookmark = bookmark
            self.isReadOnly = isReadOnly
            self.url = try URL(resolvingPersistentBookmarkData: bookmark)
        }
        
        init(url: URL, isReadOnly: Bool = false) throws {
            self.path = url.path
            self.bookmark = try url.persistentBookmarkData(isReadyOnly: isReadOnly)
            self.isReadOnly = isReadOnly
            self.url = url
        }
        
        fileprivate init(path: String, remoteBookmark: Data) {
            self.path = path
            self.bookmark = Data()
            self.isReadOnly = false
            self.url = URL(fileURLWithPath: path)
            self.remoteBookmark = remoteBookmark
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decode(String.self, forKey: .path)
            bookmark = try container.decode(Data.self, forKey: .bookmark)
            isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
            remoteBookmark = try container.decodeIfPresent(Data.self, forKey: .remoteBookmark)
            url = try URL(resolvingPersistentBookmarkData: bookmark)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encode(bookmark, forKey: .bookmark)
            try container.encode(isReadOnly, forKey: .isReadOnly)
            try container.encodeIfPresent(remoteBookmark, forKey: .remoteBookmark)
        }
    }
    
    struct Window: Codable, Equatable {
        var scale: CGFloat = 1.0
        
        var origin: CGPoint = .zero
        
        var isToolbarVisible: Bool = true
        
        var isKeyboardVisible: Bool = false
        
        var isDisplayZoomLocked: Bool = true
        
        private enum CodingKeys: String, CodingKey {
            case scale = "Scale"
            case origin = "Origin"
            case isToolbarVisible = "ToolbarVisible"
            case isKeyboardVisible = "KeyboardVisible"
            case isDisplayZoomLocked = "DisplayZoomLocked"
        }
        
        init() {
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scale = try container.decode(CGFloat.self, forKey: .scale)
            origin = try container.decode(CGPoint.self, forKey: .origin)
            isToolbarVisible = try container.decode(Bool.self, forKey: .isToolbarVisible)
            isKeyboardVisible = try container.decode(Bool.self, forKey: .isKeyboardVisible)
            isDisplayZoomLocked = try container.decode(Bool.self, forKey: .isDisplayZoomLocked)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scale, forKey: .scale)
            try container.encode(origin, forKey: .origin)
            try container.encode(isToolbarVisible, forKey: .isToolbarVisible)
            try container.encode(isKeyboardVisible, forKey: .isKeyboardVisible)
            try container.encode(isDisplayZoomLocked, forKey: .isDisplayZoomLocked)
        }
    }
}
