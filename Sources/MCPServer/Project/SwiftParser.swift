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
    let whereClause: String?
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

        // join modifiers into alternation: "final|public|..."
        let modifiersPattern = ObjectTypeModifier.allCases.map { $0.rawValue }.joined(separator: "|")

        for objectType in ObjectType.allCases {
            let flavorName = objectType.rawValue
            // Pattern: optional modifiers, keyword (class/enum/...), then capture name (anything up to ":" or "{" or newline)
            // We allow backticks and generics inside the captured name; we'll trim " where ..." out of the name later.
            let pattern = "(?:\\b(?:\(modifiersPattern))\\b|\\s)*\\b\(flavorName)\\b\\s+([^\\{\\n\\r:]+)(?:\\s*:\\s*([^\\{]*))?"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }

            for result in regex.matches(in: txt, options: [], range: range) {
                // result.range(at: 1) -> captured name-like portion
                // result.range(at: 2) -> optional inheritsFrom (after colon)
                guard result.range(at: 1).location != NSNotFound else { continue }
                var rawName = (txt as NSString).substring(with: result.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)

                // If name contains a 'where' clause inline (unlikely), strip it off from name
                if let whereRangeInName = rawName.range(of: "\\bwhere\\b", options: .regularExpression) {
                    rawName = String(rawName[..<whereRangeInName.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Remove surrounding backticks if present
                rawName = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "`")).trimmingCharacters(in: .whitespacesAndNewlines)
                if rawName.isEmpty { continue }
                let name = rawName

                var inheritsFrom: String? = nil
                if result.numberOfRanges >= 3, result.range(at: 2).location != NSNotFound {
                    inheritsFrom = (txt as NSString).substring(with: result.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if inheritsFrom?.isEmpty == true { inheritsFrom = nil }
                }

                // Extract modifiers that appear before the keyword (take the substring from start of match up to flavorName)
                let fullMatchRange = result.range
                let fullMatchingString = (txt as NSString).substring(with: fullMatchRange)
                let beforeKeyword = fullMatchingString.components(separatedBy: flavorName)[0]
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
                    // header is portion between end of regex match and the opening brace
                    let headerStart = fullMatchRange.location + fullMatchRange.length
                    let headerLength = max(0, openBraceLocation - headerStart)
                    var whereClause: String? = nil
                    if headerLength > 0 {
                        let headerRange = NSRange(location: headerStart, length: headerLength)
                        let header = (txt as NSString).substring(with: headerRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Look for where clause in header (top-level), e.g. "where T: Equatable"
                        if let whereRegex = try? NSRegularExpression(pattern: "\\bwhere\\b", options: [.caseInsensitive]) {
                            let headerNS = header as NSString
                            let hRange = NSRange(location: 0, length: headerNS.length)
                            if let whereMatch = whereRegex.firstMatch(in: header, options: [], range: hRange) {
                                // take everything from 'where' to the end of header
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

                    definitions.append(ObjectDefinition(
                        objectType: objectType,
                        name: name,
                        modifiers: usedModifiers.isEmpty ? nil : usedModifiers.unique,
                        inheritsFrom: inheritsFrom,
                        whereClause: whereClause,
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
            let parameters = parseParameters(paramsString)

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
        var result: [FunctionParameter] = []

        for rawPart in rawParts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }

            // Split on top-level ':' to determine if there is a name/label part.
            let colonSplit = splitTopLevel(part, separator: ":")

            if colonSplit.count == 1 {
                // No top-level colon -> this is a type-only parameter (e.g. enum case: b(Int))
                let typeOnly = part.trimmingCharacters(in: .whitespacesAndNewlines)
                // Use '_' as a placeholder name, label nil (tests don't assert the name for such cases)
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
                if label == "_" { label = nil }
            }

            result.append(FunctionParameter(name: name, label: label, type: typePart))
        }

        return result
    }
}
