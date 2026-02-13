//
//  ToolResult.swift
//  MCPServer
// 
//  Created by: tomieq on 13/02/2026
//
import Foundation

struct ToolResult: Codable {
    let content: [Content]
    
    init(_ values: [String]) {
        self.content = values.map { Content(type: "text", text: $0) }
    }
    struct Content: Codable {
        let type: String
        let text: String
    }
}
