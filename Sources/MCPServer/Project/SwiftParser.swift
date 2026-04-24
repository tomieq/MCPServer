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
    case open, indirect, dynamic
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

struct EnumParameter: Equatable, Hashable, Codable {
    let name: String?
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
    let params: [EnumParameter]?
}

struct ObjectVariable: Equatable, Hashable, Codable {
    let name: String
    let type: String?
}

struct ObjectDefinition: Equatable, Hashable, Codable {
    let objectType: ObjectType
    let name: String
    let modifiers: [ObjectTypeModifier]?
    let inheritsFrom: String?
    let whereClause: String?
    let functions: [ObjectMethod]?
    let variables: [ObjectVariable]?
    let cases: [EnumCase]?
    let objects: [ObjectDefinition]?
}

struct SwiftFile: Equatable, Hashable, Codable {
    let objects: [ObjectDefinition]
    let imports: [String]?
}

struct ParserConfig {
    let includeFunctions: Bool
    let includeEnumCases: Bool
    let includeVariables: Bool
    
    init(includeFunctions: Bool = true,
         includeEnumCases: Bool = true,
         includeVariables: Bool = true) {
        self.includeFunctions = includeFunctions
        self.includeEnumCases = includeEnumCases
        self.includeVariables = includeVariables
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

        // compute map of brace-depth at each UTF-16 offset so we can know which regex matches are top-level
        let utf16 = Array(txt.utf16)
        var depthAtUtf16 = [Int](repeating: 0, count: utf16.count + 1)
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevWasEscape = false
        for i in 0..<utf16.count {
            // depth before processing character at utf16 index i
            depthAtUtf16[i] = depth
            let ch = utf16[i]
            if ch == 92 { // backslash '\'
                prevWasEscape.toggle()
                continue
            }
            if !prevWasEscape {
                if ch == 34 && !inSingleQuote { // double quote
                    inDoubleQuote.toggle()
                } else if ch == 39 && !inDoubleQuote { // single quote
                    inSingleQuote.toggle()
                } else if !inSingleQuote && !inDoubleQuote {
                    if ch == 123 { // '{'
                        depth += 1
                    } else if ch == 125 { // '}'
                        depth = max(0, depth - 1)
                    }
                }
            } else {
                // consumed an escape; reset
                prevWasEscape = false
            }
        }
        // final position
        depthAtUtf16[utf16.count] = depth


        var definitions: [ObjectDefinition] = []
        let range = NSRange(location: 0, length: txt.utf16.count)
        
        // join modifiers into alternation: "final|public|..."
        let modifiersPattern = ObjectTypeModifier.allCases.map { $0.rawValue }.joined(separator: "|")
        
        for objectType in ObjectType.allCases {
            let rawObjectType = objectType.rawValue
            // Capture the whole header part (everything up to the opening brace or newline),
            // so we can correctly parse generics that include ':' inside them.
            let pattern = "(?:\\b(?:\(modifiersPattern))\\b|\\s)*\\b\(rawObjectType)\\b\\s+([^\\{\\n\\r]+)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            
            for result in regex.matches(in: txt, options: [], range: range) {
                guard result.range(at: 1).location != NSNotFound else { continue }

                let matchStart = result.range.location
                let matchDepth = (matchStart >= 0 && matchStart < depthAtUtf16.count) ? depthAtUtf16[matchStart] : 0
                if matchDepth != 0 {
                    // to dopasowanie jest wewnątrz jakiegoś bloku (np. inside a class/enum) —
                    // zostanie znalezione, kiedy zrobimy rekurencyjne parse na bodyContent.
                    continue
                }
                // rawHeader contains name + optional inheritance + optional where-clause (everything between keyword and '{')
                var rawHeader = (txt as NSString).substring(with: result.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Find 'where' at top-level in rawHeader (simple regex search; OK because where usually top-level here)
                var whereClause: String? = nil
                if let whereRegex = try? NSRegularExpression(pattern: "\\bwhere\\b", options: [.caseInsensitive]) {
                    let headerNS = rawHeader as NSString
                    let hRange = NSRange(location: 0, length: headerNS.length)
                    if let whereMatch = whereRegex.firstMatch(in: rawHeader, options: [], range: hRange) {
                        let whereStart = whereMatch.range.location
                        if whereStart < headerNS.length {
                            let wherePart = headerNS.substring(from: whereStart).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !wherePart.isEmpty {
                                whereClause = wherePart
                                // remove where part from rawHeader so it doesn't pollute name/inherits parsing
                                rawHeader = headerNS.substring(to: whereStart).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                }
                
                // Find top-level ':' separator (outside generics/parentheses/brackets/quotes).
                var inheritsFrom: String? = nil
                if let colonIndex = topLevelIndex(of: ":", in: rawHeader) {
                    // split by that colon
                    let idx = colonIndex
                    let namePart = String(rawHeader[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let inheritsPartStart = rawHeader.index(after: idx)
                    let inheritsPart = String(rawHeader[inheritsPartStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    rawHeader = namePart
                    if !inheritsPart.isEmpty {
                        inheritsFrom = inheritsPart
                    }
                }
                
                // rawHeader now should be just the name (including generics, backticks, etc.)
                var rawName = rawHeader
                // Remove surrounding backticks if present
                rawName = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "`")).trimmingCharacters(in: .whitespacesAndNewlines)
                if rawName.isEmpty { continue }
                let name = rawName
                
                // Extract modifiers that appear before the keyword (take the substring from start of match up to flavorName)
                let fullMatchRange = result.range
                let fullMatchingString = (txt as NSString).substring(with: fullMatchRange)
                let beforeKeyword = fullMatchingString.components(separatedBy: rawObjectType)[0]
                let usedModifiers = beforeKeyword
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .compactMap { ObjectTypeModifier(rawValue: $0) }
                
                // Find body starting location (after the full match) and attempt to find matching brace block
                let searchStart = fullMatchRange.location + fullMatchRange.length
                if let bodyRange = findClosingBraceRange(in: txt, startingAt: searchStart) {
                    // bodyRange.location is the first character INSIDE the braces (openBraceLocation + 1)
                    // therefore the open brace position is bodyRange.location - 1 (if > 0)
                    let openBraceLocation = max(0, bodyRange.location - 1)
                    // header is portion between end of regex match and the opening brace (might be empty because we captured header earlier)
                    let headerStart = fullMatchRange.location + fullMatchRange.length
                    let headerLength = max(0, openBraceLocation - headerStart)
                    if whereClause == nil && headerLength > 0 {
                        // Fallback: try to extract where clause from header area (if not already extracted)
                        let headerRange = NSRange(location: headerStart, length: headerLength)
                        let header = (txt as NSString).substring(with: headerRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        if let whereRegex = try? NSRegularExpression(pattern: "\\bwhere\\b", options: [.caseInsensitive]) {
                            let headerNS = header as NSString
                            let hRange = NSRange(location: 0, length: headerNS.length)
                            if let whereMatch = whereRegex.firstMatch(in: header, options: [], range: hRange) {
                                let whereStart = whereMatch.range.location
                                if whereStart < headerNS.length {
                                    let wherePart = headerNS.substring(from: whereStart).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !wherePart.isEmpty {
                                        whereClause = wherePart
                                    }
                                }
                            }
                        }
                    }
                    
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
                    var variables: [ObjectVariable] = []
                    if config.includeVariables {
                        variables = harvestVariables(from: bodyContent)
                    }
                    
                    let nestedObjects = Self.parseObjecsTypes(fileContent: bodyContent, config: config)
                    
                    definitions.append(ObjectDefinition(
                        objectType: objectType,
                        name: name,
                        modifiers: usedModifiers.isEmpty ? nil : usedModifiers.unique,
                        inheritsFrom: inheritsFrom,
                        whereClause: whereClause,
                        functions: functions.isEmpty ? nil : functions,
                        variables: variables.isEmpty ? nil : variables,
                        cases: cases?.isEmpty == false ? cases : nil,
                        objects: nestedObjects.isEmpty ? nil : nestedObjects
                    ))
                }
            }
        }
        return definitions
    }
    
    // Helper: find index of a separator character that's at top-level (not inside <>, (), [], {}, or quotes)
    private static func topLevelIndex(of separator: Character, in s: String) -> String.Index? {
        var stack: [Character] = []
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevWasEscape = false
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                prevWasEscape.toggle()
                i = s.index(after: i)
                continue
            }
            if !prevWasEscape {
                if ch == "\"" && !inSingleQuote {
                    inDoubleQuote.toggle()
                } else if ch == "'" && !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if !inSingleQuote && !inDoubleQuote {
                    // IMPORTANT: check separator before push/pop of bracket characters,
                    // so separators that are also bracket chars (like '{') are reported.
                    if ch == separator && stack.isEmpty {
                        return i
                    }
                    if ch == "(" || ch == "[" || ch == "{" || ch == "<" {
                        stack.append(ch)
                    } else if ch == ")" || ch == "]" || ch == "}" || ch == ">" {
                        if !stack.isEmpty { stack.removeLast() }
                    }
                }
            }
            prevWasEscape = false
            i = s.index(after: i)
        }
        return nil
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
    
    private static func findClosingDelimiter(in ns: NSString, startingAt location: Int, openChar: unichar, closeChar: unichar) -> Int? {
        let length = ns.length
        guard location < length else { return nil }
        var depth = 0
        var i = location
        while i < length {
            let ch = ns.character(at: i)
            if ch == openChar { depth += 1 }
            else if ch == closeChar {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }
    
    private static func harvestMethods(from body: String) -> [ObjectMethod] {
        var methods: [ObjectMethod] = []
        let ns = body as NSString
        let fullLength = ns.length
        
        guard let funcRegex = try? NSRegularExpression(pattern: "\\bfunc\\b", options: []) else { return [] }
        let matches = funcRegex.matches(in: body, options: [], range: NSRange(location: 0, length: fullLength))
        
        for match in matches {
            let funcPos = match.range.location
            let funcEnd = funcPos + match.range.length
            
            // Find the next opening parenthesis '(' for parameters
            let searchRangeForParen = NSRange(location: funcEnd, length: fullLength - funcEnd)
            let parenRange = ns.range(of: "(", options: [], range: searchRangeForParen)
            guard parenRange.location != NSNotFound else { continue }
            
            // Find matching closing parenthesis
            guard let closingParenIndex = findClosingDelimiter(in: ns, startingAt: parenRange.location, openChar: unichar(("(" as Character).unicodeScalars.first!.value), closeChar: unichar((")" as Character).unicodeScalars.first!.value)) else { continue }
            
            // Extract name + possible generics between func and '('
            let nameRange = NSRange(location: funcEnd, length: parenRange.location - funcEnd)
            var nameAndGeneric = (ns.substring(with: nameRange)).trimmingCharacters(in: .whitespacesAndNewlines)
            if nameAndGeneric.isEmpty { continue }
            
            // Determine method name: take up to first whitespace (keeps generics attached)
            let nameTokens = nameAndGeneric.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let name = nameTokens.first ?? nameAndGeneric
            
            // Extract parameters string (content between parentheses)
            let paramsContentRange = NSRange(location: parenRange.location + 1, length: closingParenIndex - (parenRange.location + 1))
            let paramsString = ns.substring(with: paramsContentRange)
            let parameters = parseFunctionParameters(paramsString)
            
            // Determine modifiers: look backwards from funcPos to start of line (or start of body)
            var lineStart = funcPos
            while lineStart > 0 {
                let ch = ns.character(at: lineStart - 1)
                if ch == 10 || ch == 13 || ch == 123 || ch == 125 { // newline or brace
                    break
                }
                lineStart -= 1
            }
            let preFuncRange = NSRange(location: lineStart, length: funcPos - lineStart)
            let preFunc = (preFuncRange.length > 0) ? ns.substring(with: preFuncRange) : ""
            let preTokens = (preFunc + " ")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            let modifiers = preTokens.compactMap { MethodModifier(rawValue: $0) }
            
            // Extract signature suffix (from after closing paren up to next '{' or end-of-body or ';')
            let suffixSearchStart = closingParenIndex + 1
            var suffixEnd = fullLength
            if suffixSearchStart < fullLength {
                // Try to find the next opening brace '{' for function body
                let searchRangeForBrace = NSRange(location: suffixSearchStart, length: fullLength - suffixSearchStart)
                let braceRange = ns.range(of: "{", options: [], range: searchRangeForBrace)
                if braceRange.location != NSNotFound {
                    suffixEnd = braceRange.location
                } else {
                    // fallback: end of line
                    if let nlRange = ns.substring(from: suffixSearchStart).rangeOfCharacter(from: CharacterSet.newlines) {
                        let idx = ns.substring(from: suffixSearchStart).distance(from: ns.substring(from: suffixSearchStart).startIndex, to: nlRange.lowerBound)
                        suffixEnd = suffixSearchStart + idx
                    }
                }
            }
            let suffixRange = NSRange(location: suffixSearchStart, length: max(0, suffixEnd - suffixSearchStart))
            let signatureSuffix = (suffixRange.length > 0) ? ns.substring(with: suffixRange) : ""
            
            // Detect throws/rethrows and async
            let canThrow = signatureSuffix.contains("throws") || signatureSuffix.contains("rethrows")
            // Determine return type
            var returnType = "Void"
            if let arrowRange = signatureSuffix.range(of: "->") {
                let afterArrow = signatureSuffix[arrowRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                // cut off at first occurrence of these delimiters/keywords
                let delimiters = [" where ", " throws", " rethrows", " async", "{", ";", "\n", "\r"]
                var cutIndex = afterArrow.endIndex
                for d in delimiters {
                    if let r = afterArrow.range(of: d) {
                        if r.lowerBound < cutIndex { cutIndex = r.lowerBound }
                    }
                }
                let extracted = afterArrow[..<cutIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    returnType = String(extracted)
                }
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
        // Skanuj ciało znak po znaku, utrzymując licznik depth tylko dla nawiasów klamrowych.
        // Przetwarzaj tylko linie, które występują przy depth == 0 (top-level w enumie).
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevWasEscape = false
        var currentLine = ""
        
        func processLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // interesują nas tylko linie rozpoczynające się deklaracją 'case'
            // dopuszczamy także 'case' bezpośrednio (rzadko), lub 'case ' z dalszą treścią
            guard trimmed.hasPrefix("case ") || trimmed == "case" else { return }
            
            // Usuń słowo "case" i przetwórz resztę
            let afterCase = String(trimmed.dropFirst(min(4, trimmed.count))).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !afterCase.isEmpty else { return }
            
            // Podziel listę przypadków top-level (mogą być oddzielone przecinkami)
            let items = splitTopLevel(afterCase, separator: ",")
            for item in items {
                let it = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if it.isEmpty { continue }
                
                var name = it
                var params: [EnumParameter]? = nil
                var rawValue: String? = nil
                
                // top-level '=' -> raw value
                let rawSplit = splitTopLevel(it, separator: "=")
                if rawSplit.count >= 2 {
                    rawValue = rawSplit[1]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    name = rawSplit[0].trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // payload parameters: name(params)
                if let openIdx = name.firstIndex(of: "("),
                   let closeIdx = name.lastIndex(of: ")"),
                   openIdx < closeIdx {
                    let paramsStr = String(name[name.index(after: openIdx)..<closeIdx])
                    let parsedParams = parseEnumParameters(paramsStr)
                    params = parsedParams.isEmpty ? nil : parsedParams
                    name = String(name[..<openIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                cases.append(EnumCase(name: name, rawValue: rawValue, params: params))
            }
        }
        
        for ch in body {
            if ch == "\\" {
                prevWasEscape.toggle()
                currentLine.append(ch)
                continue
            }
            if !prevWasEscape {
                if ch == "\"" && !inSingleQuote {
                    inDoubleQuote.toggle()
                } else if ch == "'" && !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if !inSingleQuote && !inDoubleQuote {
                    if ch == "{" {
                        depth += 1
                    } else if ch == "}" {
                        depth = max(0, depth - 1)
                    }
                }
            }
            prevWasEscape = false
            
            if ch == "\n" || ch == "\r" {
                if depth == 0 {
                    processLine(currentLine)
                }
                currentLine = ""
            } else {
                currentLine.append(ch)
            }
        }
        // ostatnia linia
        if !currentLine.isEmpty && depth == 0 {
            processLine(currentLine)
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
    
    private static func parseFunctionParameters(_ paramsString: String) -> [FunctionParameter] {
        let trimmed = paramsString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        
        let rawParts = splitTopLevel(trimmed, separator: ",")
        var result: [FunctionParameter] = []
        
        for rawPart in rawParts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }
            
            // Split on top-level ':' to determine if there is a name/label part.
            let colonSplit = splitTopLevel(part, separator: ":")
            
            if colonSplit.count == 1 {
                // No top-level colon -> this is a type-only parameter (e.g. enum case: b(Int))
                let typeOnly = part.trimmingCharacters(in: .whitespacesAndNewlines)
                // Use '_' as a placeholder name, label nil (tests/consumer code may expect placeholder)
                result.append(FunctionParameter(name: "_", label: nil, type: typeOnly))
                continue
            }
            
            // There is a top-level colon: first piece is the name part, rest combined is the type (may contain additional ':' inside generics etc)
            let namePart = colonSplit[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let typePartJoined = colonSplit.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove default value if present by splitting on top-level '='
            let eqSplit = splitTopLevel(typePartJoined, separator: "=")
            let typePart = eqSplit.first!.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Parse name/label tokens (externalLabel internalName) or just internalName
            let nameTokens = namePart
                .split(separator: " ", omittingEmptySubsequences: true)
                .map { String($0) }
            
            var label: String? = nil
            var name: String
            
            if nameTokens.count == 1 {
                name = nameTokens[0]
                // single token -> no explicit external label provided; keep label nil
                if name == "_" { /* internal name is '_' -> keep label nil and name as '_' */ }
            } else {
                label = nameTokens.first
                name = nameTokens.last ?? nameTokens.joined()
            }
            
            result.append(FunctionParameter(name: name, label: label, type: typePart))
        }
        
        return result
    }
    
    private static func parseEnumParameters(_ paramsString: String) -> [EnumParameter] {
        let trimmed = paramsString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        
        let rawParts = splitTopLevel(trimmed, separator: ",")
        var result: [EnumParameter] = []
        
        for rawPart in rawParts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }
            
            // Split on top-level ':' to determine if there is a name part.
            let colonSplit = splitTopLevel(part, separator: ":")
            
            if colonSplit.count == 1 {
                // No top-level colon -> this is a type-only parameter (e.g. .case(Int, String))
                let typeOnly = part.trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(EnumParameter(name: nil, type: typeOnly))
                continue
            }
            
            // There is a top-level colon: first piece is the name part, rest combined is the type
            let namePart = colonSplit[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let typePartJoined = colonSplit.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove default value if present by splitting on top-level '=' (rare in enum payloads)
            let eqSplit = splitTopLevel(typePartJoined, separator: "=")
            let typePart = eqSplit.first!.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // namePart could be "label name" or just "name"
            let nameTokens = namePart
                .split(separator: " ", omittingEmptySubsequences: true)
                .map { String($0) }
            
            var name: String? = nil
            if nameTokens.isEmpty {
                name = nil
            } else if nameTokens.count == 1 {
                name = (nameTokens[0] == "_") ? nil : nameTokens[0]
            } else {
                // take the internal name (last token), ignore external label for enum parameters
                let last = nameTokens.last!
                name = (last == "_") ? nil : last
            }
            
            result.append(EnumParameter(name: name, type: typePart))
        }
        
        return result
    }
    
    private static func harvestVariables(from body: String) -> [ObjectVariable] {
        var vars: [ObjectVariable] = []
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var prevWasEscape = false
        var currentLine = ""
        
        func processLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // Tokenize by whitespace to find 'let'/'var' and any preceding tokens (possible modifiers)
            let tokens = trimmed
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            var keywordIndex: Int? = nil
            for (i, t) in tokens.enumerated() {
                if t == "let" || t == "var" {
                    keywordIndex = i
                    break
                }
            }
            guard let kIdx = keywordIndex else { return }
            
            // If there are tokens before the keyword that look like modifiers, skip the line.
            if kIdx > 0 {
                let preTokens = Array(tokens[0..<kIdx])
                var hasModifier = false
                for pre in preTokens {
                    let stripped = pre.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
                    if ObjectTypeModifier(rawValue: stripped) != nil {
                        hasModifier = true
                        break
                    }
                    for mod in ObjectTypeModifier.allCases {
                        if stripped.hasPrefix(mod.rawValue) {
                            hasModifier = true
                            break
                        }
                    }
                    if hasModifier { break }
                }
                if hasModifier { return }
            }
            
            // find position of keyword in the original trimmed string to extract remainder accurately
            guard let kwRange = trimmed.range(of: tokens[kIdx]) else { return }
            let afterKeyword = String(trimmed[kwRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !afterKeyword.isEmpty else { return }
            
            // Split top-level by commas to get declarations within this single let/var statement
            let rawDecls = splitTopLevel(afterKeyword, separator: ",")
            if rawDecls.isEmpty { return }
            
            struct ParsedDecl {
                var namePart: String
                var typePart: String?  // nil if none present in this decl
            }
            var parsed: [ParsedDecl] = []
            
            for raw in rawDecls {
                let d = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if d.isEmpty { continue }
                if d.first == "(" { continue } // ignore tuple/destructuring
                
                // Split on top-level ':' to see if this declarator contains a type annotation
                let colonSplit = splitTopLevel(d, separator: ":")
                if colonSplit.count >= 2 {
                    let namePart = colonSplit[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let rest = colonSplit.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                    // remove initializer if present (top-level '=')
                    let eqSplit = splitTopLevel(rest, separator: "=")
                    let typePart = eqSplit.first!.trimmingCharacters(in: .whitespacesAndNewlines)
                    parsed.append(ParsedDecl(namePart: namePart, typePart: typePart.isEmpty ? nil : typePart))
                } else {
                    // no colon here; maybe has initializer "x = ..." or just a name
                    let eqSplit = splitTopLevel(d, separator: "=")
                    let namePart = eqSplit[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    parsed.append(ParsedDecl(namePart: namePart, typePart: nil))
                }
            }
            
            // Propagate type annotations backwards: "a, b: Int" -> a gets Int
            var currentType: String? = nil
            for idx in stride(from: parsed.count - 1, through: 0, by: -1) {
                if let tp = parsed[idx].typePart, !tp.isEmpty {
                    currentType = tp
                } else if let cur = currentType {
                    parsed[idx].typePart = cur
                }
            }
            
            // Convert parsed declarations into ObjectVariable entries
            for p in parsed {
                let namePart = p.namePart.trimmingCharacters(in: .whitespacesAndNewlines)
                let nameTokens = namePart
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                guard let rawName = nameTokens.last else { continue }
                if rawName.contains("(") || rawName.contains("[") || rawName.contains("{") { continue }
                let name = rawName.trimmingCharacters(in: CharacterSet(charactersIn: ":,;"))
                
                // Clean up type: if it contains a top-level '{' (computed property body), strip from there.
                var finalType: String?
                if let tp = p.typePart {
                    let tpTrim = tp.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let braceIdx = topLevelIndex(of: "{", in: tpTrim) {
                        let beforeBrace = String(tpTrim[..<braceIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        finalType = beforeBrace.isEmpty ? nil : beforeBrace
                    } else {
                        finalType = tpTrim.isEmpty ? nil : tpTrim
                    }
                }
                
                vars.append(ObjectVariable(name: name, type: finalType))
            }
        }
        
        for ch in body {
            if ch == "\\" {
                prevWasEscape.toggle()
                currentLine.append(ch)
                continue
            }
            if !prevWasEscape {
                if ch == "\"" && !inSingleQuote {
                    inDoubleQuote.toggle()
                } else if ch == "'" && !inDoubleQuote {
                    inSingleQuote.toggle()
                } else if !inSingleQuote && !inDoubleQuote {
                    if ch == "{" {
                        depth += 1
                    } else if ch == "}" {
                        depth = max(0, depth - 1)
                    }
                }
            }
            prevWasEscape = false
            
            if ch == "\n" || ch == "\r" || ch == ";" {
                if depth == 0 {
                    processLine(currentLine)
                }
                currentLine = ""
            } else {
                currentLine.append(ch)
            }
        }
        if !currentLine.isEmpty && depth == 0 {
            processLine(currentLine)
        }
        
        return vars
    }
}
