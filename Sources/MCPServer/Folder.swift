//
//  Folder.swift
//  MCPServer
// 
//  Created by: tomieq on 16/02/2026
//
import Foundation

class Folder {
    let realUrl = URL(fileURLWithPath: "/Users/tomaskuc/dev/LokiAgent/Sources/")
    private let virtualUrl = URL(fileURLWithPath: "/" )
    private let fileManager = FileManager.default
    
    func files() -> [String] {
        self.crawl(url: self.realUrl, prefix: "/")
    }
    
    func realPath(_ virtualPath: String) -> String {
        realUrl.appendingPathComponent(virtualPath).path()
    }
    
    func virtualPath(_ realPath: String) -> String {
        realPath.replacingOccurrences(of: realUrl.path(), with: virtualUrl.path())
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

