//
//  ToolsList.swift
//  MCPServer
// 
//  Created by: tomieq on 13/02/2026
//
import Foundation

struct ToolsList: Codable {
    let tools: [Schema]
    
    struct Schema: Codable {
        let name: String
        let description: String
        let inputSchema: ToolParameter
    }
    
    init(_ tools: [Schema]) {
        self.tools = tools
    }
}
