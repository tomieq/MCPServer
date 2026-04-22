//
//  PetEngine.swift
//  MCPServer
// 
//  Created by: tomieq on 22/04/2026
//
import Swifter

class PetEngine: Engine {
    let tools = ToolsList([
        .init(name: CommandName.get_pets,
              description: "Returns an array of objects with all possible pets (petID, kind, name)",
              inputSchema:
                ToolParameter(type: .object,
                              properties: [:],
                              required: [])
             ),
        .init(name: CommandName.get_pet_price,
              description: "Returns the price of given pet. Call it for one of the pets from get_pets. If you want prices for many pets, you need to call this multiple times.",
              inputSchema:
                ToolParameter(type: .object,
                              properties: ["petID": .init(type: .integer, description: "petID of returned from get_pets")],
                              required: ["petID"])
             )
       ])
    
    
    
    func call(_ command: CommandName, body: HttpRequestBody) throws -> ToolResult {
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
            struct Pet: Codable {
                let petID: Int
            }
            let command: Command<Pet> = try body.decode()
            guard let petID = command.params?.arguments?.petID else {
                logger.e("Missing petID")
                dto = ToolResult([])
                break
            }
            logger.i("Returning price for petID: \(petID)")
            dto = ToolResult(["\(Int.random(in: 25...100)) zł"])
        }
        return dto
    }
    
    
}

