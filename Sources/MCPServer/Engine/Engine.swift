//
//  Engine.swift
//  MCPServer
// 
//  Created by: tomieq on 22/04/2026
//
import Swifter

protocol Engine {
    var tools: ToolsList { get }
    func call(_ command: CommandName, body: HttpRequestBody) throws -> ToolResult
}

