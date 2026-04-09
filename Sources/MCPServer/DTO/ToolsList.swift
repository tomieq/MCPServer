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
        
        init(name: String, description: String, inputSchema: ToolParameter) {
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
        }
        
        init(name: CustomStringConvertible, description: String, inputSchema: ToolParameter) {
            self.name = name.description
            self.description = description
            self.inputSchema = inputSchema
        }
        
    }
    
    init(_ tools: [Schema]) {
        self.tools = tools
    }
}
