//
//  ObjectTypeHarvester.swift
//  MCPServer
// 
//  Created by: tomieq on 24/04/2026
//
import Foundation
import Logger

enum ObjectType: String, CaseIterable, Codable {
    case `class`
    case `enum`
    case `struct`
    case `protocol`
    case `actor`
    case `extension`
}

enum ObjectTypeModifier: String, CaseIterable, Codable {
    case final
    case `public`
    case `internal`
    case `private`
    case `fileprivate`
}

struct NamedType: Equatable, Hashable, Codable {
    let objectType: ObjectType
    let name: String
    let modifiers: [ObjectTypeModifier]
    let inheritsFrom: String? // Nowe pole: przechowuje nazwę klasy bazowej lub protokołów
    
    var isPublic: Bool {
        self.modifiers.contains(.public)
    }
}

extension NamedType: CustomStringConvertible {
    var description: String {
        let inheritance = inheritsFrom != nil ? " inherits from \(inheritsFrom!)" : ""
        return "\(self.objectType) \(self.name)\(inheritance) with modifiers: \(self.modifiers.map{ $0.rawValue })"
    }
}

struct ObjectTypeHarvester {
    private static let logger = Logger(ObjectTypeHarvester.self)
    
    static func getObjectTypes(fileContent txt: String) -> [NamedType] {
        var foundTypes: [NamedType] = []
        let range = NSRange(location: 0, length: txt.utf16.count)
        let modifiers = ObjectTypeModifier.allCases.map { $0.rawValue }.joined(separator: "|")
        
        for objectType in ObjectType.allCases {
            let flavorName = objectType.rawValue
            
            // ZMODYFIKOWANY WZORZEC:
            // 1. (\(modifiers)|\\s)*\\s\(flavorName)\\s -> Modyfikatory i typ
            // 2. ([A-Z][a-zA-Z0-9_]+) -> Grupa 1: Nazwa typu
            // 3. (\\s*:\\s*([^\\{]*))? -> Grupa 2 i 3: Opcjonalny dwukropek i wszystko aż do znaku '{'
            let pattern = "(\(modifiers)|\\s)*\\s\(flavorName)\\s([A-Z][a-zA-Z0-9_]+)(\\s*:\\s*([^\\{]*))?"
            
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            
            for result in regex.matches(in: txt, options: [], range: range) {
                // Wyciąganie całego dopasowanego ciągu dla modyfikatorów
                let fullMatchRange = result.range
                let fullMatchingString = (txt as NSString).substring(with: fullMatchRange)
                
                // Wyciąganie nazwy typu (Grupa 2)
                let nameRange = result.range(at: 2)
                let name = (txt as NSString).substring(with: nameRange).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Wyciąganie dziedziczenia (Grupa 4 - treść po dwukropku)
                var inheritsFrom: String? = nil
                if result.range(at: 4).location != NSNotFound {
                    inheritsFrom = (txt as NSString).substring(with: result.range(at: 4))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Wyciąganie modyfikatorów (wszystko przed słowem kluczowym typu)
                let splitted = fullMatchingString.components(separatedBy: flavorName)
                let usedModifiers = splitted[0]
                    .components(separatedBy: .whitespacesAndNewlines)
                    .compactMap { ObjectTypeModifier(rawValue: $0) }
                
                let namedType = NamedType(
                    objectType: objectType,
                    name: name,
                    modifiers: usedModifiers,
                    inheritsFrom: inheritsFrom
                )
                
                foundTypes.append(namedType)
                Self.logger.i("Found \(namedType)")
            }
        }
        return foundTypes
    }
}

