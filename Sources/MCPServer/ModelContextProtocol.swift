//
//  ModelContextProtocol.swift
//  MCPServer
//
//  Created by: tomieq on 13/02/2026
//
import Foundation
import SwiftExtensions
import Swifter
import Logger

enum MCPCallError: Error {
    case toolNotFound
}
class ModelContextProtocol {
    private let logger = Logger(ModelContextProtocol.self)
    let engines: [Engine] = [
        PetEngine(),
        RandomEngine()
    ]
    
    func initialize(id: Int) -> MCPResponse<Initialize> {
        let dto = Initialize(protocolVersion: "2025-03-26",
                             serverInfo: .init(name: "SwiftMCP",
                                               version: "1.0.0"),
                             capabilities: .init(tools: .init(listChanged: false)),
                             instructions: engines.map { $0.instructions }.joined(separator: "\n")
        )
        return MCPResponse(id: id, dto)
    }
    
    func list(id: Int) -> MCPResponse<ToolsList> {
        return MCPResponse(id: id, ToolsList(engines.flatMap { $0.tools }))
    }
    
    func call(id: Int, name: String, body: HttpRequestBody) throws -> MCPResponse<ToolResult> {
        guard let engine = (engines.first{ $0.canHandle(name) }) else {
            throw MCPCallError.toolNotFound
        }
        return MCPResponse(id: id, try engine.call(name, body: body))
    }
}
