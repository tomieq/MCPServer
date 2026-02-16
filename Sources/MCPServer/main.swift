import Foundation
import Swifter
import Logger
import Dispatch


#if os(Linux)
setvbuf(stdout, nil, _IONBF, 0)
#endif

let folder = Folder()
let fileCache = FileCache(folder: folder)

let logger = Logger("MCPServer")
let rest = try RestServer(folder: folder, cache: fileCache)
let folderMonitor = try FolderMonitor(folder: folder.realUrl) { change in
    fileCache.fileChanged(change)
}
RunLoop.main.run()
