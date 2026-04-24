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

    func test_modifiers_inheritance_and_whereClause() throws {
        let src = """
        public final class MyClass<T>: SuperClass where T: Codable {
            func doSomething() -> Int { return 0 }
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .class, name: "MyClass")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.modifiers, [.public, .final]) // order preserved from source
        XCTAssertEqual(obj?.inheritsFrom, "SuperClass")
        XCTAssertEqual(obj?.whereClause, "where T: Codable")
        let method = findMethod(obj!, methodName: "doSomething")
        XCTAssertNotNil(method)
        XCTAssertEqual(method?.returnType, "Int")
    }

    func test_extension_with_where() throws {
        let src = """
        extension Array where Element: Equatable {
            func foo() {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .extension, name: "Array")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?.whereClause, "where Element: Equatable")
        let method = findMethod(obj!, methodName: "foo")
        XCTAssertNotNil(method)
        XCTAssertEqual(method?.returnType, "Void")
    }

    func test_enum_cases_multiple_and_associated_and_raw() throws {
        let src = """
        enum E {
            case a, b(Int), c = 3, d(name: String), e(_ value: (Int, String))
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "E")
        XCTAssertNotNil(obj)
        // Check cases existence and details
        let caseA = findEnumCase(obj!, caseName: "a")
        XCTAssertNotNil(caseA)
        XCTAssertNil(caseA?.params)
        let caseB = findEnumCase(obj!, caseName: "b")
        XCTAssertNotNil(caseB)
        XCTAssertEqual(caseB?.params?.count, 1)
        XCTAssertEqual(caseB?.params?.first?.type, "Int")
        let caseC = findEnumCase(obj!, caseName: "c")
        XCTAssertEqual(caseC?.rawValue, "3")
        let caseD = findEnumCase(obj!, caseName: "d")
        XCTAssertEqual(caseD?.params?.first?.name, "name")
        // underscore local label behavior (external label _ should become nil)
        let caseE = findEnumCase(obj!, caseName: "e")
        XCTAssertNotNil(caseE)
        XCTAssertEqual(caseE?.params?.first?.name, "value")
    }

    func test_function_signatures_various() throws {
        let src = """
        struct S {
            public func foo() {}
            func add(a: Int, b label: String = "x") -> String { return \"\" }
            @objc static func objcMethod(name: String?) throws -> [String: Any] {}
            func complex(param: (Int, String), closure: (Int) -> Void) async -> Result<Void, Error> { fatalError() }
            func `weird-name`() {}
            private class func classMethod() {}
            func externalLabel(_ internalName: Int) {}
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .struct, name: "S")
        XCTAssertNotNil(obj)
        // foo
        let foo = findMethod(obj!, methodName: "foo")
        XCTAssertNotNil(foo)
        XCTAssertEqual(foo?.returnType, "Void")
        // add
        let add = findMethod(obj!, methodName: "add")
        XCTAssertNotNil(add)
        XCTAssertEqual(add?.params?.count, 2)
        XCTAssertEqual(add?.params?[0].name, "a")
        XCTAssertEqual(add?.params?[0].type, "Int")
        XCTAssertEqual(add?.params?[1].label, "b")
        XCTAssertEqual(add?.params?[1].type, "String")
        XCTAssertEqual(add?.returnType, "String")
        // objcMethod
        let objc = findMethod(obj!, methodName: "objcMethod")
        XCTAssertNotNil(objc)
        XCTAssertTrue(objc!.canThrow)
        XCTAssertTrue(objc!.modifiers?.contains(.objc) ?? false)
        XCTAssertTrue(objc!.modifiers?.contains(.static) ?? false)
        XCTAssertEqual(objc?.returnType, "[String: Any]")
        // complex return extraction should capture Result<Void, Error>
        let complex = findMethod(obj!, methodName: "complex")
        XCTAssertNotNil(complex)
        XCTAssertEqual(complex?.returnType, "Result<Void, Error>")
        // weird name kept (backticks trimmed at type-level; method-level name might include backticks)
        let weird = findMethod(obj!, methodName: "`weird-name`") ?? findMethod(obj!, methodName: "weird-name")
        XCTAssertNotNil(weird)
        // classMethod modifiers
        let classM = findMethod(obj!, methodName: "classMethod")
        XCTAssertNotNil(classM)
        XCTAssertTrue(classM?.modifiers?.contains(.class) ?? false)
        XCTAssertTrue(classM?.modifiers?.contains(.private) ?? false)
        // external label underscore behavior
        let external = findMethod(obj!, methodName: "externalLabel")
        XCTAssertNotNil(external)
        XCTAssertEqual(external?.params?.first?.label, nil) // '_' external -> nil or treated specially
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
            case third = \"x\"
        }
        """
        let file = SwiftParser.parseFile(fileContent: src)
        let obj = findObject(in: file, type: .enum, name: "Complex")
        XCTAssertNotNil(obj)
        let first = findEnumCase(obj!, caseName: "first")
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.params?.count, 2)
        XCTAssertEqual(first?.params?[0].type, "String")
        let second = findEnumCase(obj!, caseName: "second")
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.params?.count, 2)
        XCTAssertEqual(second?.params?[0].name, "point")
        XCTAssertEqual(second?.params?[1].type, "[String: Any]")
        let third = findEnumCase(obj!, caseName: "third")
        XCTAssertEqual(third?.rawValue, "\"x\"")
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
        let f = findMethod(obj!, methodName: "complicated")
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.params?.count, 2)
        XCTAssertEqual(f?.params?[0].type, "(Int, String)")
        XCTAssertEqual(f?.params?[1].type, "(Result<Int, Error>) -> Void")
        XCTAssertEqual(f?.returnType, "((Int) -> String)?")
    }

}

