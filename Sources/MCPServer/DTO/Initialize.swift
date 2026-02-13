//
//  Initialize.swift
//  MCPServer
// 
//  Created by: tomieq on 13/02/2026
//
import Foundation

struct Initialize: Codable {
    let protocolVersion: String
    let serverInfo: ServerInfo
    let capabilities: Capability
    let instructions: String

    struct ServerInfo: Codable {
        let name: String
        let version: String
    }

    struct Capability: Codable {
        let tools: Tools
        // let resources = Tools(listChanged: true)
        // let prompts = Tools(listChanged: true)
        // let logging = Tools(listChanged: nil)
    }
    
    struct Tools: Codable {
        let listChanged: Bool?
    }
}
