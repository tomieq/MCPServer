import Foundation
import Swifter

@main
struct MCPServer {
    static func main() throws {
        let server = HttpServer()
        server.name = "MCP Server"
        server.middleware.append { request, header in
            print("Request \(request.id) \(request.method) \(request.path) from \(request.clientIP ?? "")")
            request.onFinished { summary in
                print("Request \(summary.requestID) finished with \(summary.responseCode) [\(summary.responseSize)] in \(String(format: "%.3f", summary.durationInSeconds)) seconds")
            }
            return nil
        }
        try server.start(8080, forceIPv4: true)
        print("Server started on port \(try server.port)")
        RunLoop.main.run()
    }
}
