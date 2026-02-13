import Foundation

struct MCPError: Codable {
    let jsonrpc: String
    let id: Int?
    let error: ErrorSchema
    
    struct ErrorSchema: Codable {
        let code: Int
        let message: String
    }
}
