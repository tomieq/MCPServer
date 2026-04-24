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
    let params: [FunctionParameter]?
    let returnType: String
    let canThrow: Bool
}

struct EnumCase: Equatable, Hashable, Codable {
    let name: String
    let rawValue: String?
    let params: [FunctionParameter]?
}

struct ObjectDefinition: Equatable, Hashable, Codable {
    let objectType: ObjectType
    let name: String
    let modifiers: [ObjectTypeModifier]?
    let inheritsFrom: String?
    let functions: [ObjectMethod]?
    let cases: [EnumCase]?
}

struct SwiftFile: Equatable, Hashable, Codable {
    let objects: [ObjectDefinition]
    let imports: [String]?
}

struct ParserConfig {
    let includeFunctions: Bool
    let includeEnumCases: Bool
    
    init(includeFunctions: Bool = true, includeEnumCases: Bool = true) {
        self.includeFunctions = includeFunctions
        self.includeEnumCases = includeEnumCases
    }
}
// MARK: - Parser
struct SwiftParser {
    
    static func parseFile(fileContent txt: String, config: ParserConfig = ParserConfig()) -> SwiftFile {
        let imports = harvestImports(from: txt)
        return SwiftFile(objects: Self.parseObjecsTypes(fileContent: txt, config: config),
                         imports: imports.isEmpty ? nil : imports)
    }
    
    static func parseObjecsTypes(fileContent txt: String, config: ParserConfig) -> [ObjectDefinition] {
        let txt = CommentRemover.removeComments(txt)
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
                    
                    let functions: [ObjectMethod]
                    if config.includeFunctions {
                        functions = harvestMethods(from: bodyContent)
                    } else {
                        functions = []
                    }
                    let cases: [EnumCase]?
                    if config.includeEnumCases, objectType == .enum {
                        cases = harvestEnumCases(from: bodyContent)
                    } else {
                        cases = nil
                    }
                    
                    definitions.append(ObjectDefinition(
                        objectType: objectType,
                        name: name,
                        modifiers: usedModifiers.isEmpty ? nil : usedModifiers.unique,
                        inheritsFrom: inheritsFrom,
                        functions: functions.isEmpty ? nil : functions,
                        cases: cases?.isEmpty == false ? cases : nil
                    ))
                }
            }
        }
        return definitions
    }

    private static func harvestImports(from txt: String) -> [String] {
        var imports: [String] = []
        // Changed ([a-zA-Z0-9_.,\s]+) to ([a-zA-Z0-9_., ]+)
        // to prevent matching newline characters (\n \r)
        let importPattern = "^import\\s+([a-zA-Z0-9_., ]+)"
        
        guard let regex = try? NSRegularExpression(pattern: importPattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(location: 0, length: txt.utf16.count)
        
        for result in regex.matches(in: txt, options: [], range: range) {
            if result.range(at: 1).location != NSNotFound {
                let importsLine = (txt as NSString).substring(with: result.range(at: 1))
                // Rozdzielanie importów oddzielonych przecinkami
                let modules = importsLine.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .map { $0.components(separatedBy: " as ")[0].trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                imports.append(contentsOf: modules)
            }
        }
        return imports.unique
    }

private static func findClosingBraceRange(in txt: String, startingAt location: Int) -> NSRange? {
    let ns = txt as NSString
    let length = ns.length
    guard location < length else { return nil }
    let searchRange = NSRange(location: location, length: length - location)
    let openRange = ns.range(of: "{", options: [], range: searchRange)
    guard openRange.location != NSNotFound else { return nil }

    let openChar: unichar = 123  // '{'
    let closeChar: unichar = 125 // '}'
    var braceCount = 0
    var i = openRange.location
    while i < length {
        let ch = ns.character(at: i)
        if ch == openChar { braceCount += 1 }
        else if ch == closeChar { braceCount -= 1 }
        if braceCount == 0 {
            let startPos = openRange.location + 1
            return NSRange(location: startPos, length: i - startPos)
        }
        i += 1
    }
    return nil
}

    private static func harvestMethods(from body: String) -> [ObjectMethod] {
        var methods: [ObjectMethod] = []
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
            let signatureSuffix = (body as NSString).substring(with: result.range(at: 5))
            
            let canThrow = signatureSuffix.contains("throws")
            var returnType = "Void"
            if let arrowRange = signatureSuffix.range(of: "->") {
                let afterArrow = signatureSuffix[arrowRange.upperBound...]
                let cleanReturn = afterArrow.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "{")[0]
                    .components(separatedBy: ";")[0]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                returnType = cleanReturn.isEmpty ? "Void" : String(cleanReturn)
            }
            
            methods.append(ObjectMethod(
                name: name,
                modifiers: modifiers.isEmpty ? nil : modifiers,
                params: parameters.isEmpty ? nil : parameters,
                returnType: returnType,
                canThrow: canThrow
            ))
        }
        return methods
    }

    private static func harvestEnumCases(from body: String) -> [EnumCase] {
        var cases: [EnumCase] = []
        // find "case " occurrences and capture until end of line or '}' — simpler: line-based approach
        let pattern = "^\\s*case\\s+([^\\n\\r{]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let range = NSRange(location: 0, length: body.utf16.count)
        for result in regex.matches(in: body, options: [], range: range) {
            if result.range(at: 1).location == NSNotFound { continue }
            let list = (body as NSString).substring(with: result.range(at: 1))
            let items = splitTopLevel(list, separator: ",")
            for item in items {
                let it = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if it.isEmpty { continue }
                // possible forms:
                // name
                // name = raw
                // name(params)
                // name(params) = raw
                // parse name + params + raw
                var name = it
                var params: [FunctionParameter]? = nil
                var rawValue: String? = nil

                // extract raw value (top-level '=')
                let rawSplit = splitTopLevel(it, separator: "=")
                if rawSplit.count >= 2 {
                    rawValue = rawSplit[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    name = rawSplit[0].trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // extract params if present
                if let openIdx = name.firstIndex(of: "("), let closeIdx = name.lastIndex(of: ")"), openIdx < closeIdx {
                    let paramsStr = String(name[name.index(after: openIdx)..<closeIdx])
                    let parsedParams = parseParameters(paramsStr)
                    params = parsedParams.isEmpty ? nil : parsedParams
                    name = name[..<openIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                cases.append(EnumCase(name: String(name), rawValue: rawValue, params: params))
            }
        }
        return cases
    }
    // Utility: split top-level by separator, ignoruje zagnieżdżone nawiasy i stringi
    private static func splitTopLevel(_ s: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var stack: [Character] = []
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevWasEscape = false

        for ch in s {
            if ch == "\\" {
                prevWasEscape.toggle()
                current.append(ch)
                continue
            }
            if !prevWasEscape {
                if ch == "\"" && !inSingleQuote {
                    inDoubleQuote.toggle()
                } else if ch == "'" && !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if !inSingleQuote && !inDoubleQuote {
                    if ch == "(" || ch == "[" || ch == "{" || ch == "<" {
                        stack.append(ch)
                    } else if ch == ")" || ch == "]" || ch == "}" || ch == ">" {
                        if !stack.isEmpty { stack.removeLast() }
                    } else if ch == separator && stack.isEmpty {
                        parts.append(current)
                        current = ""
                        continue
                    }
                }
            }
            // reset escape flag unless current char was backslash handled above
            prevWasEscape = false
            current.append(ch)
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
    
private static func parseParameters(_ paramsString: String) -> [FunctionParameter] {
    let trimmed = paramsString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return [] }

    let rawParts = splitTopLevel(trimmed, separator: ",")
    return rawParts.compactMap { rawPart in
        let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !part.isEmpty else { return nil }
        // split on first ':' (type separator)
        guard let colonIdx = part.firstIndex(of: ":") else { return nil }
        let namePart = part[..<colonIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        var typePart = part[part.index(after: colonIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
        // remove default value if present: split on '=', but only top-level
        if let eqIdx = splitTopLevel(String(typePart), separator: "=").first?.startIndex {
            // keep left of '=' already handled by splitTopLevel: simpler to split by '=' top-level
            let left = splitTopLevel(String(typePart), separator: "=")[0]
            typePart = left.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // no default
            // nothing
        }
        // parse name / label
        let nameTokens = namePart.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
        var label: String? = nil
        var name: String
        if nameTokens.count == 1 {
            name = nameTokens[0]
            if name == "_" { name = "_" } // local name '_' is allowed; you may decide to treat label as nil
            if name == "_" { label = nil } // external name is _
        } else {
            label = nameTokens.first
            name = nameTokens.last ?? nameTokens.joined()
            if label == "_" { label = nil }
        }
        return FunctionParameter(name: name, label: label, type: typePart)
    }
}
}
