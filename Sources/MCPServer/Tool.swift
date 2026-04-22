import Foundation

struct Tool: Codable {
    let name: String
    let description: String
    let parameters: [ToolParameter]
}


struct ToolParameter: Codable {
    let type: ValueType // usually .object and empty properties
    let properties: [String: Property] // pair name and type
    let required: [String] // required property names

    struct Property: Codable {
        let type: ValueType
        let description: String
    }
    
    init(type: ValueType = .object, properties: [String : Property], required: [String]) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

enum ValueType: String, Codable {
    case string
    case integer
    case number // default for Double
    case boolean
    case array
    case object
    case date
    case uuid
    case any
}
