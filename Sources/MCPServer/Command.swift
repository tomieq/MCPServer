import Foundation

struct Command: Codable {
    let id: Int?
    let method: String
    let params: Params?

    struct Params: Codable {
        let protocolVersion: String?
        let name: String?
    }
}
