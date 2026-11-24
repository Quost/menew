import XCTest
@testable import Menew

// Transformações de texto da paleta: funções puras de String para String?

final class TextTransformTests: XCTestCase {
    func testCamelCase() {
        XCTAssertEqual(TextTransform.camel.apply("hello world foo"), "helloWorldFoo")
        XCTAssertEqual(TextTransform.camel.apply("foo-bar_baz"), "fooBarBaz")
        XCTAssertEqual(TextTransform.camel.apply("Hello World"), "helloWorld")
    }

    func testSnakeCase() {
        XCTAssertEqual(TextTransform.snake.apply("helloWorld"), "hello_world")
        XCTAssertEqual(TextTransform.snake.apply("Hello World"), "hello_world")
        XCTAssertEqual(TextTransform.snake.apply("HTTPServer"), "http_server")
        XCTAssertEqual(TextTransform.snake.apply("Olá mundo"), "ola_mundo")
    }

    func testKebabCase() {
        XCTAssertEqual(TextTransform.kebab.apply("Hello World"), "hello-world")
        XCTAssertEqual(TextTransform.kebab.apply("some_snake_case"), "some-snake-case")
        XCTAssertEqual(TextTransform.kebab.apply("one two\nthree four"), "one-two\nthree-four")   // por linha
    }

    func testTitleAndSentenceCase() {
        XCTAssertEqual(TextTransform.title.apply("hello world"), "Hello World")
        XCTAssertEqual(TextTransform.sentence.apply("hello. WORLD! ok"), "Hello. World! Ok")
    }

    func testUpperLowerAndNoAccents() {
        XCTAssertEqual(TextTransform.upper.apply("abc"), "ABC")
        XCTAssertEqual(TextTransform.lower.apply("ABC"), "abc")
        XCTAssertEqual(TextTransform.noAccents.apply("Olá, açaí"), "Ola, acai")
    }

    func testTrimCollapsesWhitespace() {
        XCTAssertEqual(TextTransform.trim.apply("  a   b  \n\n\n  c  "), "a b\n\nc")
    }

    func testLineTransforms() {
        XCTAssertEqual(TextTransform.sortLines.apply("banana\napple\ncherry"), "apple\nbanana\ncherry")
        XCTAssertEqual(TextTransform.sortLines.apply("b\na\n"), "a\nb\n")   // mantém a quebra do fim
        XCTAssertEqual(TextTransform.reverseLines.apply("1\n2\n3"), "3\n2\n1")
        XCTAssertEqual(TextTransform.uniqueLines.apply("a\nb\na\nc\nb"), "a\nb\nc")
    }

    func testJSONMinifyAndPrettyRoundTrip() throws {
        XCTAssertEqual(TextTransform.jsonMinify.apply("{ \"a\" : 1 }"), "{\"a\":1}")
        XCTAssertEqual(TextTransform.jsonMinify.apply("[1, 2, 3]"), "[1,2,3]")
        XCTAssertEqual(TextTransform.jsonMinify.apply("{\"u\": \"http://x.y/z\"}"), "{\"u\":\"http://x.y/z\"}")   // sem escapar "/"

        let pretty = try XCTUnwrap(TextTransform.jsonPretty.apply("{\"a\":[1,2]}"))
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertEqual(TextTransform.jsonMinify.apply(pretty), "{\"a\":[1,2]}")
    }

    func testInvalidJSONIsNil() {
        XCTAssertNil(TextTransform.jsonPretty.apply("{not json"))
        XCTAssertNil(TextTransform.jsonMinify.apply("{not json"))
        XCTAssertNil(TextTransform.jsonMinify.apply(""))
    }

    func testBase64() {
        XCTAssertEqual(TextTransform.base64Encode.apply("hello"), "aGVsbG8=")
        XCTAssertEqual(TextTransform.base64Decode.apply("aGVsbG8="), "hello")
        XCTAssertEqual(TextTransform.base64Decode.apply("aGVsbG8"), "hello")   // aceita sem o "=" do fim
        let text = "Olá, mundo ✓ 123"
        let encoded = TextTransform.base64Encode.apply(text)
        XCTAssertEqual(encoded.flatMap { TextTransform.base64Decode.apply($0) }, text)
    }

    func testInvalidBase64IsNil() {
        XCTAssertNil(TextTransform.base64Decode.apply("!!!"))
        XCTAssertNil(TextTransform.base64Decode.apply(""))
        XCTAssertNil(TextTransform.base64Decode.apply("/w=="))   // byte 0xFF: não é UTF-8
    }

    func testURLEncodeDecode() {
        XCTAssertEqual(TextTransform.urlEncode.apply("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9")
        XCTAssertEqual(TextTransform.urlDecode.apply("a%20b%26c%3Dd%2F%C3%A9"), "a b&c=d/é")
        XCTAssertEqual(TextTransform.urlDecode.apply("a%20b+c"), "a b c")   // "+" vira espaço
        let text = "q=olá mundo&x=1/2?"
        XCTAssertEqual(TextTransform.urlEncode.apply(text).flatMap { TextTransform.urlDecode.apply($0) }, text)
        XCTAssertNil(TextTransform.urlDecode.apply("%zz"))
    }

    func testJWT() throws {
        func b64url(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        let token = "\(b64url("{\"alg\":\"none\"}")).\(b64url("{\"sub\":\"42\"}")).sig"
        let out = try XCTUnwrap(TextTransform.jwt.apply("Bearer " + token))
        XCTAssertTrue(out.contains("\"alg\""))
        XCTAssertTrue(out.contains("\"sub\""))
        XCTAssertNil(TextTransform.jwt.apply("not-a-jwt"))
    }
}
