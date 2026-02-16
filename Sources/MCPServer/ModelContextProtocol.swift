//
//  ModelContextProtocol.swift
//  MCPServer
//
//  Created by: tomieq on 13/02/2026
//
import Foundation
import SwiftExtensions
import Swifter

class ModelContextProtocol {
    func initialize(id: Int) -> MCPResponse<Initialize> {
        let dto = Initialize(protocolVersion: "2025-03-26",
                             serverInfo: .init(name: "SwiftMCP",
                                               version: "1.0.0"),
                             capabilities: .init(tools: .init(listChanged: false)),
                             instructions: "Provides available pets"
        )
        return MCPResponse(id: id, dto)
    }
    
    func list(id: Int) -> MCPResponse<ToolsList> {
        let dto = ToolsList([
            
            .init(name: "list_files",
                  description: "Returns the tree structure of all files in the project.",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [:],
                                  required: [])
                 ),
            .init(name: "read_file",
                  description: "Use this tool if you need to view the contents of an existing file.",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [
                                    "filepath": .init(type: "string", description: "The absolute path of the file to read")
                                  ],
                                  required: ["filepath"])
                 ),
            .init(name: "rename_file",
                  description: "Use this tool if you need to chnage the file's name or move the file within the project",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [
                                    "oldFilepath": .init(type: "string", description: "Current absolute path of the file"),
                                    "newFilepath": .init(type: "string", description: "New absolute path of to be set for the file")
                                  ],
                                  required: ["oldFilepath", "newFilepath"])
                 ),
            .init(name: "override_file",
                  description: "Use this tool if you need to override the content of an existing file.",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [
                                    "filepath": .init(type: "string", description: "The absolute path of the file to write to"),
                                    "content": .init(type: "string", description: "The utf8 content to write")
                                  ],
                                  required: ["filepath", "content"])
                 ),
            .init(name: "create_file",
                  description: "Create a new file. Only use this when a file doesn't exist and should be created",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [
                                    "filepath": .init(type: "string", description: "The absolute path of the file to create"),
                                    "content": .init(type: "string", description: "The utf8 content to write")
                                  ],
                                  required: ["filepath", "content"])
                 ),
            .init(name: "delete_file",
                  description: "Use this tool if you need to completely delete a file",
                  inputSchema:
                    ToolParameter(type: "object",
                                  properties: [
                                    "filepath": .init(type: "string", description: "The absolute path of the file to delete")
                                  ],
                                  required: ["filepath"])
                 ),
        ])
        return MCPResponse(id: id, dto)
    }
    
    func function(id: Int, name: String, body: HttpRequestBody) throws -> MCPResponse<ToolResult> {
        let dto: ToolResult
        switch name {
        case "list_files":
            let folder = Folder("/project/")
            dto = ToolResult(folder.files())
        case "read_file":
            
            struct File: Codable {
                let filepath: String
            }
            let command: Command<File> = try body.decode()
            let filepath = command.params?.arguments?.filepath ?? ""
            logger.d("Read file content from: \(command.params?.arguments?.filepath ?? "")")
            let content = try? String(contentsOfFile: filepath, encoding: .utf8)
            dto = ToolResult([content.or("File not found at \(filepath)")])
        case "rename_file":
            struct Action: Codable {
                let oldFilepath: String
                let newFilepath: String
            }
            let command: Command<Action> = try body.decode()
            let filepath = command.params?.arguments?.oldFilepath ?? ""
            let newFilepath = command.params?.arguments?.newFilepath ?? ""
            
            guard FileManager.default.fileExists(atPath: filepath) else {
                dto = ToolResult(["File not found at \(filepath)"])
                break
            }
            guard FileManager.default.fileExists(atPath: newFilepath).not else {
                dto = ToolResult(["File already exists at \(filepath)"])
                break
            }
            try? FileManager.default.moveItem(atPath: filepath, toPath: newFilepath)
            dto = ToolResult(["File has been moved from \(filepath) to \(newFilepath)"])
        case "override_file":
            struct Action: Codable {
                let filepath: String
                let content: String
            }
            let command: Command<Action> = try body.decode()
            let filepath = command.params?.arguments?.filepath ?? ""
            let content = command.params?.arguments?.content ?? ""
            
            guard FileManager.default.fileExists(atPath: filepath) else {
                dto = ToolResult(["File not found at \(filepath)"])
                break
            }
            try? content.write(toFile: filepath, atomically: true, encoding: .utf8)
            dto = ToolResult(["The content has been written to \(filepath)"])
        case "create_file":
            struct Action: Codable {
                let filepath: String
                let content: String
            }
            let command: Command<Action> = try body.decode()
            let filepath = command.params?.arguments?.filepath ?? ""
            let content = command.params?.arguments?.content ?? ""
            
            guard FileManager.default.fileExists(atPath: filepath).not else {
                dto = ToolResult(["File already exists at \(filepath)"])
                break
            }
            try? content.write(toFile: filepath, atomically: true, encoding: .utf8)
            dto = ToolResult(["File has been created at \(filepath)"])
        case "delete_file":
            struct Action: Codable {
                let filepath: String
            }
            let command: Command<Action> = try body.decode()
            let filepath = command.params?.arguments?.filepath ?? ""
            
            guard FileManager.default.fileExists(atPath: filepath) else {
                dto = ToolResult(["File \(filepath) does not exists"])
                break
            }
            try? FileManager.default.removeItem(atPath: filepath)
            dto = ToolResult(["File \(filepath) has been deleted"])
        default:
            logger.e("Unsupported function: \(name)")
            dto = ToolResult([])
        }
        return MCPResponse(id: id, dto)
    }
}
