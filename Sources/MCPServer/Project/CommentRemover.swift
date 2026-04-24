//
//  CommentRemover.swift
//  MCPServer
// 
//  Created by: tomieq on 24/04/2026
//

import Foundation

enum CommentRemover {
    static func removeComments(_ content: String) -> String {
        var content = content
        while let openIndex = content.getFirstIndex(for: .openMultiline),
              let closeIndex = content.getFirstIndex(for: .closeMultiline) {
            content.removeSubrange(openIndex...closeIndex + 1)
        }
        let lines = content.components(separatedBy: .newlines)
        let linesWithoutComment = lines
            .filter {
                $0.trimmingCharacters(in: .whitespaces)
                    .starts(with: "//")
                    .not
            }
            .map { (line: String) -> String in
                if let index = line.getFirstIndex(for: .singleLine) {
                    return line[0...index - 1]
                }
                return line
            }
        return linesWithoutComment.joined(separator: "\n")
    }
}

fileprivate enum CommentSign {
    case singleLine
    case openMultiline
    case closeMultiline

    var sign: (Character, Character) {
        switch self {
        case .singleLine:
            return ("/", "/")
        case .openMultiline:
            return ("/", "*")
        case .closeMultiline:
            return ("*", "/")
        }
    }
}

fileprivate extension String {
    func getFirstIndex(for type: CommentSign) -> Int? {
        var isInsideQuote = false
        let expected = type.sign
        for (index, character) in self.enumerated() {
            let nextIndex = index + 1
            if character == "\"" { isInsideQuote.toggle() }
            if character == expected.0, isInsideQuote.not, nextIndex < self.count, self[nextIndex] == expected.1 {
                return index
            }
        }
        return nil
    }
    mutating func removeSubrange(_ range: ClosedRange<Int>) {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        self.removeSubrange(startIndex..<index(startIndex, offsetBy: range.count))
    }
}

fileprivate extension String {
    subscript(offset: Int) -> Character {
        self[index(startIndex, offsetBy: offset)]
    }

    subscript(range: Range<Int>) -> String {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        return String(self[startIndex..<index(startIndex, offsetBy: range.count)])
    }

    subscript(range: ClosedRange<Int>) -> String {
        let startIndex = index(self.startIndex, offsetBy: range.lowerBound)
        return String(self[startIndex..<index(startIndex, offsetBy: range.count)])
    }

    subscript(range: PartialRangeFrom<Int>) -> String {
        String(self[index(startIndex, offsetBy: range.lowerBound)...])
    }

    subscript(range: PartialRangeThrough<Int>) -> String {
        String(self[...index(startIndex, offsetBy: range.upperBound)])
    }

    subscript(range: PartialRangeUpTo<Int>) -> String {
        String(self[..<index(startIndex, offsetBy: range.upperBound)])
    }
}
