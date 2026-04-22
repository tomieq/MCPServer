//
//  String+JSON.swift
//  MCPServer
// 
//  Created by: tomieq on 22/04/2026
//

import Foundation

extension String {
    
    var prettyJSON: String? {
        guard !self.isEmpty else {
            return nil
        }
        
        guard let data = self.data(using: .utf8) else {
            return nil
        }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                return prettyString
            } else {
                return nil
            }
            
        } catch {
            return nil
        }
    }
}

