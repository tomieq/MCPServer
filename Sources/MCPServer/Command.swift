import Foundation

struct Command<ARGUMENT: Decodable>: Decodable {
    let id: Int?
    let method: String
    let params: Params<ARGUMENT>?

    struct Params<T: Decodable>: Decodable {
        let protocolVersion: String?
        let name: String?
        let arguments: T?
    }
}

struct NoArguments: Decodable {
    
}
