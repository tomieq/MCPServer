//
//  FileItem.swift
//  MCPServer
//
//  Created by: tomieq on 23/04/2026
//
import Foundation

indirect enum FileItem: Codable {
    case file(name: String, objects: [ObjectDefinition])
    case folder(name: String, files: [FileItem])
}

extension FileItem {
    static func harvest(url: URL, extensions: [String]) throws -> FileItem? {
        guard url.isDirectory else {
            if extensions.contains(url.pathExtension) {
                return .file(name: url.lastPathComponent,
                             objects: SwiftParser.getObjectTypes(fileContent: try String(contentsOf: url))
                )
            } else {
                return nil
            }
        }
        var files: [FileItem] = []
        for subUrl in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
            if url.isDirectory {
                if let filesInFolder = try? harvest(url: subUrl, extensions: extensions) {
                    files.append(filesInFolder)
                }
            } else if extensions.contains(subUrl.pathExtension) {
                files.append(.file(name: subUrl.lastPathComponent,
                                   objects: SwiftParser.getObjectTypes(fileContent: try String(contentsOf: url))
                                  ))
            }
        }
        if files.isEmpty { return nil }
        return .folder(name: url.lastPathComponent, files: files)
    }
}
