//
//  ToolResult.swift
//  MCPServer
// 
//  Created by: tomieq on 13/02/2026
//
import Foundation

struct ToolResult: Codable {
    let content: [Content]
    
    struct Content: Codable {
        let type: String
        let text: String
    }
}
