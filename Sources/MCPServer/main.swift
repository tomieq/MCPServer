import Foundation
import Swifter
import Logger
import Dispatch


#if os(Linux)
setvbuf(stdout, nil, _IONBF, 0)
#endif

let folder = Folder()

let logger = Logger("MCPServer")
let rest = try RestServer(folder: folder)
let folderMonitor = try FolderMonitor(folder: folder.realUrl) { url in
    
}
RunLoop.main.run()
