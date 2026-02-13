import Foundation

struct Tool: Codable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
}


struct ToolParameter: Codable {
    let type: String
    let properties: [String: Property]
    let required: [String]

    struct Property: Codable {
        let type: String
        let description: String
    }
}


