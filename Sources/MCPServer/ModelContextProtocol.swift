//
//  ModelContextProtocol.swift
//  MCPServer
//
//  Created by: tomieq on 13/02/2026
//
import Foundation

class ModelContextProtocol {
    func initialize(id: Int) -> MCPResponse<Initialize> {
        let dto = Initialize(protocolVersion: "2025-03-26",
                             serverInfo: .init(name: "SwiftMCP",
                                               version: "1.0.0"),
                             capabilities: .init(tools: .init(listChanged: false)),
                             instructions: "Provides available pets"
        )
        return MCPResponse(id: id, dto)
    }
    
    func list(id: Int) -> MCPResponse<ToolsList> {
        let dto = ToolsList([
            .init(name: "get_pet_names_v2",
                  description: "Returns an array of strings with all possible pet names",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [:],
                                  required: [])
                 )
           ])
        return MCPResponse(id: id, dto)
    }
    
    func function(id: Int, name: String) -> MCPResponse<ToolResult> {
        let dto: ToolResult
        switch name {
        case "get_pet_names_v2":
            dto = ToolResult(content: [
                .init(type: "text", text: "pies Reksio, kot Hetman, chomik Zosia")
            ])
        default:
            logger.e("Unsupported function: \(name)")
            dto = ToolResult(content: [])
        }
        return MCPResponse(id: id, dto)
    }
}
