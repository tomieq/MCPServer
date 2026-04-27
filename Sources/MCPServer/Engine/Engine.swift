//
//  Engine.swift
//  MCPServer
// 
//  Created by: tomieq on 22/04/2026
//
import Swifter

protocol Engine {
    var instructions: String { get }
    var tools: [ToolsList.Schema] { get }
    func canHandle(_ command: String) -> Bool
    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult
}

