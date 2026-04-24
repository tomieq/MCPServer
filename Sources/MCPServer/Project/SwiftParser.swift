//
//  SwiftParser.swift
//  MCPServer
// 
//  Created by: tomieq on 24/04/2026
//
import Foundation
import SwiftExtensions

// MARK: - Models

enum ObjectType: String, CaseIterable, Codable {
    case `class`, `enum`, `struct`, `protocol`, `actor`, `extension`
}

enum ObjectTypeModifier: String, CaseIterable, Codable {
    case final, `public`, `internal`, `private`, `fileprivate`
}

enum MethodModifier: String, CaseIterable, Codable {
    case `public`, `internal`, `private`, `fileprivate`, `static`, `override`, `nonisolated`, `class`
    case nonobjc = "@nonobjc", objc = "@objc"
}

struct FunctionParameter: Equatable, Hashable, Codable {
    let name: String
    let label: String?
    let type: String
}

struct ObjectMethod: Equatable, Hashable, Codable {
    let name: String
    let modifiers: [MethodModifier]?
    let parameters: [FunctionParameter]?
    let returnType: String
    let canThrow: Bool
}

struct ObjectDefinition: Equatable, Hashable, Codable {
    let objectType: ObjectType
    let objectName: String
    let modifiers: [ObjectTypeModifier]?
    let inheritsFrom: String?
    let functions: [ObjectMethod]?
}

// MARK: - Parser
struct SwiftParser {
    static func getObjectTypes(fileContent txt: String) -> [ObjectDefinition] {
        let txt  = CommentRemover.removeComments(txt)
        var definitions: [ObjectDefinition] = []
        let range = NSRange(location: 0, length: txt.utf16.count)
        let modifiersPattern = ObjectTypeModifier.allCases.map { $0.rawValue }.joined(separator: "|")
        
        for objectType in ObjectType.allCases {
            let flavorName = objectType.rawValue
            let pattern = "(\(modifiersPattern)|\\s)*\\s\(flavorName)\\s([A-Z][a-zA-Z0-9_]+)(\\s*:\\s*([^\\{]*))?"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            
            for result in regex.matches(in: txt, options: [], range: range) {
                let fullMatchRange = result.range
                let fullMatchingString = (txt as NSString).substring(with: fullMatchRange)
                let name = (txt as NSString).substring(with: result.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                var inheritsFrom: String? = nil
                if result.range(at: 4).location != NSNotFound {
                    inheritsFrom = (txt as NSString).substring(with: result.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                let usedModifiers = fullMatchingString.components(separatedBy: flavorName)[0]
                    .components(separatedBy: .whitespacesAndNewlines)
                    .compactMap { ObjectTypeModifier(rawValue: $0) }
                
                let searchStart = fullMatchRange.location + fullMatchRange.length
                if let bodyRange = findClosingBraceRange(in: txt, startingAt: searchStart) {
                    let bodyContent = (txt as NSString).substring(with: bodyRange)
                    let functions = harvestMethods(from: bodyContent)
                    definitions.append(ObjectDefinition(
                        objectType: objectType,
                        objectName: name,
                        modifiers: usedModifiers.isEmpty ? nil : usedModifiers.unique,
                        inheritsFrom: inheritsFrom,
                        functions: functions.isEmpty ? nil : functions
                    ))
                }
            }
        }
        return definitions
    }

    private static func findClosingBraceRange(in txt: String, startingAt location: Int) -> NSRange? {
        let characters = Array(txt)
        guard location < characters.count,
              let startIdx = characters[location...].firstIndex(of: "{") else { return nil }
        
        var braceCount = 0
        for i in startIdx..<characters.count {
            if characters[i] == "{" { braceCount += 1 }
            else if characters[i] == "}" { braceCount -= 1 }
            if braceCount == 0 {
                let startPos = startIdx + 1
                return NSRange(location: startPos, length: i - startPos)
            }
        }
        return nil
    }

    private static func harvestMethods(from body: String) -> [ObjectMethod] {
        var methods: [ObjectMethod] = []
        
        // MODIFIED REGEX:
        // Group 5 ([^{ \n\r]*[^{\n\r]*) now stops at the first newline or open brace
        // to prevent consuming subsequent property declarations in protocols.
        let methodPattern = "([^\\{]*?)\\bfunc\\s+([^\\(]*?)([a-z][a-zA-Z0-9_]+(?:<[^>]*>)?)\\s*\\(([^)]*)\\)([^{\\n\\r]*)"
        
        guard let regex = try? NSRegularExpression(pattern: methodPattern) else { return [] }
        let range = NSRange(location: 0, length: body.utf16.count)
        
        for result in regex.matches(in: body, options: [], range: range) {
            let preFunc = (body as NSString).substring(with: result.range(at: 1))
            let postFunc = (body as NSString).substring(with: result.range(at: 2))
            
            let allModStrings = (preFunc + " " + postFunc)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            
            let modifiers = allModStrings.compactMap { MethodModifier(rawValue: $0) }
            
            let name = (body as NSString).substring(with: result.range(at: 3))
            let paramsString = (body as NSString).substring(with: result.range(at: 4))
            let parameters = parseParameters(paramsString)
            
            // This now contains only the line containing the signature
            let signatureSuffix = (body as NSString).substring(with: result.range(at: 5))
            
            let canThrow = signatureSuffix.contains("throws")
            var returnType = "Void"
            if let arrowRange = signatureSuffix.range(of: "->") {
                let afterArrow = signatureSuffix[arrowRange.upperBound...]
                let cleanReturn = afterArrow.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "{")[0]
                    .components(separatedBy: ";")[0] // Also split by semicolon for safety
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                returnType = cleanReturn.isEmpty ? "Void" : String(cleanReturn)
            }
            
            methods.append(ObjectMethod(
                name: name,
                modifiers: modifiers.isEmpty ? nil : modifiers,
                parameters: parameters.isEmpty ? nil : parameters,
                returnType: returnType,
                canThrow: canThrow
            ))
        }
        return methods
    }

    private static func parseParameters(_ paramsString: String) -> [FunctionParameter] {
        if paramsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        return paramsString.components(separatedBy: ",").compactMap { part in
            let components = part.components(separatedBy: ":")
            guard components.count == 2 else { return nil }
            var name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var label : String?
            let nameParts = name.split(separator: " ")
            if nameParts.count == 2 {
                name = String(nameParts[1])
                label = String(nameParts[0])
            }
            var paramType = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let splittedParamType = paramType.split(separator: "=")
            if splittedParamType.count == 2 {
                paramType = String(splittedParamType[0].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return FunctionParameter(
                name: name,
                label: label,
                type: paramType
            )
        }
    }
}
