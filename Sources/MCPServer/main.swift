import Foundation
import Swifter
import Logger
import Dispatch


#if os(Linux)
setvbuf(stdout, nil, _IONBF, 0)
#endif

let path = "/Users/tomieq/dev/MCPServer/Sources"
let extenssions = ["swift"]
let files = try FileItem.harvest(url: URL(fileURLWithPath: path), extensions: extenssions)
try files?.jsonOneLine!.write(to: URL(fileURLWithPath: "project.json"), atomically: true, encoding: .utf8)
