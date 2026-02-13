//
//  MCPCommandResponse.swift
//  MCPServer
// 
//  Created by: tomieq on 13/02/2026
//
import Foundation

struct MCPResponse<T: Codable>: Codable {
    let jsonrpc: String
    let id: Int?
    let result: T
    
    init(jsonrpc: String = "2.0", id: Int, _ result: T) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
}

