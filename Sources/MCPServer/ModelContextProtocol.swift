//
//  ModelContextProtocol.swift
//  MCPServer
//
//  Created by: tomieq on 13/02/2026
//
import Foundation
import SwiftExtensions

enum Commands: String {
    case get_pets
    case get_pet_price
}

extension Commands: CustomStringConvertible {
    var description: String {
        rawValue
    }
}

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
            .init(name: Commands.get_pets,
                  description: "Returns an array of objects with all possible pets (petID, kind, name)",
                  inputSchema:
                    ToolParameter(type: .object,
                                  properties: [:],
                                  required: [])
                 ),
            .init(name: Commands.get_pet_price,
                  description: "Returns the price of given pet. Call it for one of the pets from get_pets. If you want prices for many pets, you need to call this multiple times.",
                  inputSchema:
                    ToolParameter(type: .object,
                                  properties: ["petID": .init(type: .string, description: "petID of returned from get_pets")],
                                  required: ["petID"])
                 )
           ])
        return MCPResponse(id: id, dto)
    }
    
    func function(id: Int, name: String) -> MCPResponse<ToolResult> {
        guard let command = Commands(rawValue: name) else {
            logger.e("Unsupported function: \(name)")
            return MCPResponse(id: id, ToolResult([]))
        }
        let dto: ToolResult
        switch command {
        case .get_pets:
            
            struct Pet: Codable {
                let petID: Int
                let kind: String
                let name: String
            }
            let pets: [Pet] = [
                .init(petID: 1, kind: "kot", name: "Hetman"),
                .init(petID: 2, kind: "pies", name: "Reksio"),
                .init(petID: 3, kind: "chomik", name: "Zosia")
            ]
            
            dto = ToolResult(pets.compactMap { $0.json })
        case .get_pet_price:
            dto = ToolResult(["\(Int.random(in: 25...100)) zł"])
        }
        return MCPResponse(id: id, dto)
    }
}
