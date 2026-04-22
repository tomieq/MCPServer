//
//  ModelContextProtocol.swift
//  MCPServer
//
//  Created by: tomieq on 13/02/2026
//
import Foundation
import SwiftExtensions
import Swifter

class ModelContextProtocol {
    
    let engine: Engine = PetEngine()
    
    func initialize(id: Int) -> MCPResponse<Initialize> {
        let dto = Initialize(protocolVersion: "2025-03-26",
                             serverInfo: .init(name: "SwiftMCP",
                                               version: "1.0.0"),
                             capabilities: .init(tools: .init(listChanged: false)),
                             instructions: engine.instructions
        )
        return MCPResponse(id: id, dto)
    }
    
    func list(id: Int) -> MCPResponse<ToolsList> {
        return MCPResponse(id: id, engine.tools)
    }
    
    func call(id: Int, name: String, body: HttpRequestBody) throws -> MCPResponse<ToolResult> {
        guard let command = CommandName(rawValue: name) else {
            logger.e("Unsupported function: \(name)")
            return MCPResponse(id: id, ToolResult([]))
        }
        return MCPResponse(id: id, try engine.call(command, body: body))
    }
}
