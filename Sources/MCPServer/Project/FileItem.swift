//
//  FileItem.swift
//  MCPServer
//
//  Created by: tomieq on 23/04/2026
//
import Foundation

indirect enum FileItem: Codable {
    case file(name: String, structure: SwiftFile)
    case folder(name: String, files: [FileItem])
}

extension FileItem {
    static func harvest(url: URL, extensions: [String], excludedFolders: [String] = []) throws -> FileItem? {
        guard url.isDirectory else {
            if extensions.contains(url.pathExtension) {
                return .file(name: url.lastPathComponent,
                             structure: SwiftParser.parseFile(fileContent: try String(contentsOf: url))
                )
            } else {
                return nil
            }
        }
        for excludedFolder in excludedFolders {
            if url.path.contains(excludedFolder) { return nil }
        }
        var files: [FileItem] = []
        for subUrl in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
            if url.isDirectory {
                if let filesInFolder = try? harvest(url: subUrl, extensions: extensions) {
                    files.append(filesInFolder)
                }
            } else if extensions.contains(subUrl.pathExtension) {
                files.append(.file(name: subUrl.lastPathComponent,
                                   structure: SwiftParser.parseFile(fileContent: try String(contentsOf: url))
                                  ))
            }
        }
        if files.isEmpty { return nil }
        return .folder(name: url.lastPathComponent, files: files)
    }
}
