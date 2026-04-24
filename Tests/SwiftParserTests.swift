//
//  SwiftParserTests.swift
//  MCPServer
//
//  Created by: tomieq on 24/04/2026
//

import XCTest
@testable import MCPServer
import Foundation

final class SwiftParserTests: XCTestCase {
    
    // Helper: find object by type and name
    private func findObject(in file: SwiftFile, type: ObjectType, name: String) -> ObjectDefinition? {
        return file.objects.first { $0.objectType == type && $0.name == name }
    }
    
    // Helper: find enum case by name
    private func findEnumCase(_ obj: ObjectDefinition, caseName: String) -> EnumCase? {
        guard let cases = obj.cases else { return nil }
        return cases.first { $0.name == caseName }
    }
    
    // Helper: find method by name
    private func findMethod(_ obj: ObjectDefinition, methodName: String) -> ObjectMethod? {
        guard let funcs = obj.functions else { return nil }
        return funcs.first { $0.name == methodName }
    }
    
    func testImports_singleAndMultipleAndAlias() throws {
        let src = """
        // comment
        import Foundation
        import Alamofire, SwiftyJSON as JSON
        """
        let file = SwiftParser.parseFile(fileContent: src)
        XCTAssertNotNil(file.imports)
        XCTAssertTrue(file.imports!.contains("Foundation"))
        XCTAssertTrue(file.imports!.contains("Alamofire"))
        XCTAssertTrue(file.imports!.contains("SwiftyJSON"))
        XCTAssertFalse(file.imports!.contains("JSON")) // alias removed by parser logic
    }
    
    func test_simpleClassParsing() throws {
        let src = """
        class MyClass {
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .class, name: "MyClass")
        XCTAssertNotNil(obj)
        XCTAssertNil(obj?.modifiers)
        XCTAssertNil(obj?.inheritsFrom)
        XCTAssertNil(obj?.functions)
    }
    
    func test_genericClass() throws {
        let src = """
        public struct Response<T:Codable>: Codable {
            public let value: T?
            public let errorCode : CustomError?

            public init(from decoder: Decoder) throws {
            }

            public func encode(to encoder: Encoder) throws {
            }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = file.objects.first
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj, ObjectDefinition(objectType: .struct,
                                             name: "Response<T:Codable>",
                                             modifiers: [.public],
                                             inheritsFrom: "Codable",
                                             whereClause: nil,
                                             functions: [
                                                ObjectMethod(name: "encode",
                                                             modifiers: [.public],
                                                             params: [
                                                                FunctionParameter(name: "encoder",
                                                                                  label: "to",
                                                                                  type: "Encoder")
                                                             ],
                                                             returnType: "Void",
                                                             canThrow: true)
                                             ],
                                             cases: nil,
                                            objects: nil))
    }
    
    func test_enumInClass() throws {
        let src = """
        class MyClass {
            enum CodingKeys: Codable {
                case id = "ID"
            }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = file.objects.last
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj, ObjectDefinition(objectType: .class,
                                             name: "MyClass",
                                             modifiers: nil,
                                             inheritsFrom: nil,
                                             whereClause: nil,
                                             functions: nil,
                                             cases: nil,
                                             objects: [
                                                ObjectDefinition(objectType: .enum,
                                                                 name: "CodingKeys",
                                                                 modifiers: nil,
                                                                 inheritsFrom: "Codable",
                                                                 whereClause: nil,
                                                                 functions: nil,
                                                                 cases: [
                                                                   EnumCase(name: "id",
                                                                            rawValue: "ID",
                                                                            params: nil)
                                                                 ],
                                                                 objects: nil)
                                             ]))
    }
    
    func test_simple_enum() throws {
        let src = """
        enum Endpoint {
            case start
            case end
            case UPPER_NAME
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "Endpoint")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.cases, [
            .init(name: "start", rawValue: nil, params: nil),
            .init(name: "end", rawValue: nil, params: nil),
            .init(name: "UPPER_NAME", rawValue: nil, params: nil),
        ]
        )
    }

    func test_enum_with_raw_int_value() throws {
        let src = """
        enum Endpoint: Int {
            case start = 3
            case end = 8
            case UPPER_NAME = 12
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "Endpoint")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.inheritsFrom, "Int")
        XCTAssertEqual(obj?.cases, [
            .init(name: "start", rawValue: "3", params: nil),
            .init(name: "end", rawValue: "8", params: nil),
            .init(name: "UPPER_NAME", rawValue: "12", params: nil),
        ]
        )
    }
    
    func test_enum_with_raw_string_value() throws {
        let src = """
        enum Endpoint: String {
            case start = "START"
            case end = "END"
            case UPPER_NAME
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "Endpoint")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.inheritsFrom, "String")
        XCTAssertEqual(obj?.cases, [
            .init(name: "start", rawValue: "START", params: nil),
            .init(name: "end", rawValue: "END", params: nil),
            .init(name: "UPPER_NAME", rawValue: nil, params: nil),
        ]
        )
    }
    
    func test_enum_cases_multiple_and_associated_and_raw() throws {
        let src = """
        enum E {
            case a, b(Int), c, d(name: String), e(_ value: (Int, String))
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "E")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.cases, [
            EnumCase(name: "a", rawValue: nil, params: nil),
            EnumCase(name: "b", rawValue: nil, params: [
                .init(name: nil, type: "Int")
            ]),
            EnumCase(name: "c", rawValue: nil, params: nil),
            EnumCase(name: "d", rawValue: nil, params: [
                .init(name: "name", type: "String")
            ]),
            EnumCase(name: "e", rawValue: nil, params: [
                .init(name: "value", type: "(Int, String)")
            ])
        ])
    }
    
    
    func test_enum_with_variable() throws {
        let src = """
        enum Endpoint {
            case start(Api)
            case end(Api)
        
            var url: String {
                switch self {
                case let .start(api):
                    return "\\(api.rawValue)/start"
                case let .end(api):
                    return "\\(api.rawValue)/end"
                }
            }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "Endpoint")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.cases, [
            .init(name: "start", rawValue: nil, params: [
                EnumParameter(name: nil, type: "Api")
            ]),
            .init(name: "end", rawValue: nil, params: [
                EnumParameter(name: nil, type: "Api")
            ]),
        ]
        )
    }
    
    
    func test_functionNoArguments() throws {
        let src = """
        struct S {
            public func foo() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "foo", modifiers: [.public], params: nil, returnType: "Void", canThrow: false)
        ])
    }
    
    func test_functionWithArguments() throws {
        let src = """
        struct S {
            func add(a: Int, b label: String = "x") -> String { return \"\" }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "add", modifiers: nil, params: [
                FunctionParameter(name: "a", label: nil, type: "Int"),
                FunctionParameter(name: "label", label: "b", type: "String")
            ], returnType: "String", canThrow: false)
        ])
    }
    
    func test_throwingStaticFunction() throws {
        let src = """
        struct S {
            @objc static func objcMethod(name: String?) throws -> [String: Any] {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "objcMethod", modifiers: [
                .objc, .static
            ], params: [
                FunctionParameter(name: "name", label: nil, type: "String?")
            ], returnType: "[String: Any]", canThrow: true)
        ])
    }
    
    func test_functionWithClosure() throws {
        let src = """
        struct S {
           func complex(param: (Int, String), closure: (Int) -> Void) async -> Result<Void, Error> { fatalError() }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "complex", modifiers: nil, params: [
                FunctionParameter(name: "param", label: nil, type: "(Int, String)"),
                FunctionParameter(name: "closure", label: nil, type: "(Int) -> Void")
            ], returnType: "Result<Void, Error>", canThrow: false)
        ])
    }
    
    func test_functionWeirdName() throws {
        let src = """
        struct S {
            func `weird-name`() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "`weird-name`", modifiers: nil, params: nil, returnType: "Void", canThrow: false)
        ])
    }
    
    func test_classFunction() throws {
        let src = """
        struct S {
            private class func classMethod() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "classMethod", modifiers: [
                .private, .class
            ], params: nil, returnType: "Void", canThrow: false)
        ])
    }
    
    func test_functionAnonymousLabel() throws {
        let src = """
        struct S {
            func externalLabel(_ internalName: Int) {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "externalLabel", modifiers: nil, params: [
                FunctionParameter(name: "internalName", label: "_", type: "Int")
            ], returnType: "Void", canThrow: false)
        ])
    }
    
    func test_nested_types_detection() throws {
        let src = """
        class Outer {
            struct Inner {
                func innerMethod() {}
            }
            func outerMethod() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let outer = findObject(in: file, type: .class, name: "Outer")
        XCTAssertNotNil(outer)
        let inner = findObject(in: file, type: .struct, name: "Inner")
        XCTAssertNotNil(inner)
        XCTAssertNotNil(findMethod(outer!, methodName: "outerMethod"))
        XCTAssertNotNil(findMethod(inner!, methodName: "innerMethod"))
    }
    
    func test_backtick_type_name() throws {
        let src = """
        struct `weird-name` {
            func test() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "weird-name")
        XCTAssertNotNil(obj)
        XCTAssertNotNil(findMethod(obj!, methodName: "test"))
    }
    
    func test_comments_are_removed_and_do_not_confuse_parser() throws {
        let src = """
        // class Fake { func oops() {} }
        /*
         enum Fake2 {
           case x
         }
        */
        class Real {
            // func hidden() {}
            func visible() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let fakeClass = findObject(in: file, type: .class, name: "Fake")
        XCTAssertNil(fakeClass)
        let real = findObject(in: file, type: .class, name: "Real")
        XCTAssertNotNil(real)
        XCTAssertNotNil(findMethod(real!, methodName: "visible"))
        XCTAssertNil(findMethod(real!, methodName: "hidden"))
    }
    
    func test_enum_multiple_case_lines_and_complex_associated_types() throws {
        let src = """
        enum Complex {
            case first(String, Int)
            case second(point: (Double, Double), metadata: [String: Any])
            case third
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "Complex")
        XCTAssertNotNil(obj)
        let first = findEnumCase(obj!, caseName: "first")
        XCTAssertNotNil(first)
        XCTAssertEqual(obj?.cases, [
            EnumCase(name: "first", rawValue: nil, params: [
                .init(name: nil, type: "String"),
                    .init(name: nil, type: "Int")]),
            EnumCase(name: "second", rawValue: nil, params: [
                .init(name: "point", type: "(Double, Double)"),
                .init(name: "metadata", type: "[String: Any]")
            ]),
            EnumCase(name: "third", rawValue: nil, params: nil)
        ])

    }
    
    func test_function_with_tuple_and_closure_parameters_and_defaults() throws {
        let src = """
        class C {
            func complicated(a: (Int, String) = (0, \"\"), handler: (Result<Int, Error>) -> Void = { _ in }) -> ((Int) -> String)? { nil }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .class, name: "C")
        XCTAssertNotNil(obj)
        
        XCTAssertEqual(obj?.functions, [
            ObjectMethod(name: "complicated", modifiers: nil, params: [
                FunctionParameter(name: "a", label: nil, type: "(Int, String)"),
                FunctionParameter(name: "handler", label: nil, type: "(Result<Int, Error>) -> Void")
            ], returnType: "((Int) -> String)?", canThrow: false)
        ])
    }
    
}

