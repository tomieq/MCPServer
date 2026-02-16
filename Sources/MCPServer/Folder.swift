//
//  Folder.swift
//  MCPServer
// 
//  Created by: tomieq on 16/02/2026
//
import Foundation

class Folder {
    private let fileManager = FileManager.default
    private let url: URL
    
    public init(_ url: URL) {
        self.url = url
    }
    
    public convenience init(_ path: String) {
        self.init(URL(fileURLWithPath: path))
    }
    
    func files() -> [String] {
        self.crawl(url: self.url, prefix: "/project/")
    }
    
    private func crawl(url: URL, prefix: String) -> [String] {
        let files = (try? self.fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [])) ?? []
        var output: [String] = []
        files.enumerated().forEach { index, fileUrl in
            let isDir = (try? fileUrl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let filename = fileUrl.pathComponents.last ?? "nil"
            guard filename.starts(with: ".").not else { return }
            if isDir {
                let newPrefix = prefix + filename + "/"
                let fileUrl = url.appendingPathComponent(filename)
                output.append(contentsOf: self.crawl(url: fileUrl, prefix: newPrefix))
            } else {
                output.append(prefix + filename)
            }
        }
        return output
    }
}

