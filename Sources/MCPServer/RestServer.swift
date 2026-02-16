import Foundation
import Swifter
import Logger
import SwiftExtensions

class RestServer {
    private let server = HttpServer()
    private let logger = Logger(RestServer.self)
    private let mcp = ModelContextProtocol()
    
    init() throws {
        server.name = "MCP Server"
        server.middleware.append { [unowned self] request, header in
            logger.i("Request \(request.id) \(request.method) \(request.path) from \(request.clientIP ?? "")")
            request.onFinished { [unowned self] summary in
                logger.i("Request \(summary.requestID) finished with \(summary.responseCode) [\(summary.responseSize)] in \(String(format: "%.3f", summary.durationInSeconds)) seconds")
            }
            return nil
        }
        server.post["/"] = { _, _ in
                .ok(.json(MCPError(jsonrpc: "2.0", id: nil,
                                   error: .init(code: -32601, message: "Method not found")
                                  )
                ))
        }
        server.post["/mcp"] = { [unowned self] request, _ in
//            logger.d("body: \(request.body.string?.json ?? request.body.string.or("")) queryParams: \(request.queryParams.dict)")
            let command: Command<NoArguments> = try request.body.decode()
            logger.i("command: \(command.method) \(command.params?.name ?? "")")
            
            switch command.method {
            case "initialize":
                let response = mcp.initialize(id: command.id.or(0))
                return .ok(.json(response))
            case "notifications/initialized":
                return .ok(.text(""))
            case "tools/list":
                let response = mcp.list(id: command.id.or(0))
                return .ok(.json(response))
            case "tools/call":
                let response = try mcp.function(id: command.id.or(0),
                                                name: command.params?.name ?? "",
                                                body: request.body,
                )
                logger.d(response.json!)
                return .ok(.json(response))
            default:
                break
            }
            return .internalServerError(nil)
        }
        try server.start(8080, forceIPv4: true)
        logger.i("Server started on port \(try server.port)")
    }
}
