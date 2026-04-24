//
//  ObjectTypeHarvester.swift
//  MCPServer
// 
//  Created by: tomieq on 24/04/2026
//
import Foundation
import Logger

// MARK: - Models

enum ObjectType: String, CaseIterable, Codable {
    case `class`, `enum`, `struct`, `protocol`, `actor`, `extension`
}

enum ObjectTypeModifier: String, CaseIterable, Codable {
    case final, `public`, `internal`, `private`, `fileprivate`
}

enum MethodModifier: String, CaseIterable, Codable {
    case `public`, `internal`, `private`, `fileprivate`, `static`, `override`, `@objc`
}

struct FunctionParameter: Equatable, Hashable, Codable {
    let name: String
    let label: String?
    let type: String
}

struct ObjectMethod: Equatable, Hashable, Codable {
    let name: String
    let modifiers: [MethodModifier]
    let parameters: [FunctionParameter]
    let returnType: String
    let isThrowable: Bool
}

struct NamedType: Equatable, Hashable, Codable {
    let objectType: ObjectType
    let name: String
    let modifiers: [ObjectTypeModifier]
    let inheritsFrom: String?
    let functions: [ObjectMethod]
    
    var isPublic: Bool {
        self.modifiers.contains(.public)
    }
}

extension NamedType: CustomStringConvertible {
    var description: String {
        "\(self.objectType) \(self.name) [Functions: \(functions.count)]"
    }
}

// MARK: - Parser

struct ObjectTypeHarvester {
    private static let logger = Logger(ObjectTypeHarvester.self)
    
    static func getObjectTypes(fileContent txt: String) -> [NamedType] {
        var foundTypes: [NamedType] = []
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
                    
                    foundTypes.append(NamedType(
                        objectType: objectType,
                        name: name,
                        modifiers: usedModifiers,
                        inheritsFrom: inheritsFrom,
                        functions: functions
                    ))
                }
            }
        }
        return foundTypes
    }
    
    private static func findClosingBraceRange(in txt: String, startingAt location: Int) -> NSRange? {
        let characters = Array(txt)
        guard location < characters.count,
              let startIdx = characters[location...].firstIndex(of: "{") else {
            return nil
        }
        
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
        
        // ZMODYFIKOWANY REGEX:
        // Grupa 1: Modyfikatory
        // Grupa 2: Nazwa funkcji
        // Grupa 3: Parametry
        // Grupa 4: Cała sekcja po nawiasach (zawiera throws i return type)
        let methodPattern = "((?:\\s*\(MethodModifier.allCases.map { $0.rawValue }.joined(separator: "|"))\\s*)*)\\s*func\\s+([a-z][a-zA-Z0-9_]+)\\s*\\(([^)]*)\\)([^{]*)"
        
        guard let regex = try? NSRegularExpression(pattern: methodPattern) else { return [] }
        let range = NSRange(location: 0, length: body.utf16.count)
        
        for result in regex.matches(in: body, options: [], range: range) {
            let modString = (body as NSString).substring(with: result.range(at: 1))
            let modifiers = modString.components(separatedBy: .whitespacesAndNewlines)
                .compactMap { MethodModifier(rawValue: $0) }
            
            let name = (body as NSString).substring(with: result.range(at: 2))
            let paramsString = (body as NSString).substring(with: result.range(at: 3))
            let parameters = parseParameters(paramsString)
            
            // Analiza sekcji po nawiasach (np. " throws -> String")
            let signatureSuffix = (body as NSString).substring(with: result.range(at: 4))
            
            let isThrowable = signatureSuffix.contains("throws")
            
            // Wyciąganie returnType
            var returnType = "Void" // Domyślnie Void w Swifcie
            if let arrowRange = signatureSuffix.range(of: "->") {
                let afterArrow = signatureSuffix[arrowRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                // Bierzemy tylko do pierwszego znaku nowej linii lub klamry (na wypadek braku spacji)
                let cleanReturn = afterArrow.components(separatedBy: CharacterSet(charactersIn: "{ \n\r")).first ?? "Void"
                returnType = cleanReturn
            }
            
            methods.append(ObjectMethod(
                name: name,
                modifiers: modifiers,
                parameters: parameters,
                returnType: returnType,
                isThrowable: isThrowable
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
            let nameParts = name.split(" ")
            if nameParts.count == 2 {
                name = nameParts[1]
                label = nameParts[0]
            }
            return FunctionParameter(
                name: name,
                label: label,
                type: components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
