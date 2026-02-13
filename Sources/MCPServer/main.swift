import Foundation
import Swifter
import Logger
import Dispatch


#if os(Linux)
setvbuf(stdout, nil, _IONBF, 0)
#endif

let logger = Logger("MCPServer")
let rest = try RestServer()
RunLoop.main.run()