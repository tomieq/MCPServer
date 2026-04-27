//
//  RandomEngine.swift
//  MCPServer
// 
//  Created by: tomieq on 27/04/2026
//

import Swifter
import Logger

enum RandomCommand: String, Codable {
    case get_random_number
}

extension RandomCommand: CustomStringConvertible {
    var description: String {
        rawValue
    }
}


class RandomEngine: Engine {
    private let logger = Logger(PetEngine.self)
    let instructions = "Can generate random number."
    
    func command(for rawValue: String) -> RandomCommand? {
        RandomCommand(rawValue: rawValue)
    }
    
    func canHandle(_ command: String) -> Bool {
        self.command(for: command).notNil
    }
    let tools: [ToolsList.Schema] = [
        .init(RandomCommand.get_random_number,
              description: "Generates random number",
              inputSchema:
                ToolParameter(type: .object,
                              properties: [:],
                              required: [])
             )
       ]
    
    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard let command = self.command(for: command) else {
            return ToolResult([])
        }
        let dto: ToolResult
        switch command {
        case .get_random_number:
            dto = ToolResult([Int.random(in: 1...100).description])
        }
        return dto
    }
    
    
}

