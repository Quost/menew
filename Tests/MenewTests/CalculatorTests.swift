import XCTest
@testable import Menew

// Contas, conversões de unidade e moedas da paleta. Só resultados inteiros, para não depender do separador decimal do idioma.

final class CalculatorTests: XCTestCase {
    private func value(_ q: String) -> String? { Calculator.evaluate(q)?.value }

    func testPrecedenceAndParentheses() {
        XCTAssertEqual(value("2+3*4"), "14")
        XCTAssertEqual(value("(2+3)*4"), "20")
        XCTAssertEqual(value("(2+3)*(4-1)"), "15")
        XCTAssertEqual(value("2^3^2"), "512")   // potência é associativa à direita
        XCTAssertEqual(value("2^10"), "1024")
        XCTAssertEqual(value("2 x 3"), "6")
        XCTAssertEqual(value("2(3+1)"), "8")
    }

    func testFactorialFunctionsAndUnary() {
        XCTAssertEqual(value("5!"), "120")
        XCTAssertEqual(value("sqrt(16)"), "4")
        XCTAssertEqual(value("-3+5"), "2")
    }

    func testResultKeepsTheTrimmedInputAsDetail() throws {
        let r = try XCTUnwrap(Calculator.evaluate("  2 + 2 "))
        XCTAssertEqual(r.value, "4")
        XCTAssertEqual(r.detail, "2 + 2")
    }

    func testPercent() {
        XCTAssertEqual(value("20% of 340"), "68")
        XCTAssertEqual(value("50% de 80"), "40")
        XCTAssertEqual(value("200 + 10%"), "220")
        XCTAssertEqual(value("200 - 10%"), "180")
    }

    func testInvalidInputIsNil() {
        XCTAssertNil(Calculator.evaluate(""))
        XCTAssertNil(Calculator.evaluate("   "))
        XCTAssertNil(Calculator.evaluate("42"))       // um número sozinho não é conta
        XCTAssertNil(Calculator.evaluate("hello"))
        XCTAssertNil(Calculator.evaluate("2 +"))
        XCTAssertNil(Calculator.evaluate("(2+3"))
        XCTAssertNil(Calculator.evaluate("1/0"))      // infinito não é resultado
    }

    func testUnitConversionResults() throws {
        let km = try XCTUnwrap(Calculator.evaluate("1000 m to km"))
        XCTAssertEqual(km.value, "1 km")
        XCTAssertEqual(km.detail, "1000 m")
        XCTAssertEqual(value("212 f to c"), "100 °C")
        XCTAssertEqual(value("0 c to f"), "32 °F")
        XCTAssertEqual(value("1 gb to mb"), "1000 MB")
        XCTAssertEqual(value("2 h to min"), "120 min")
    }

    func testConversionBetweenDifferentDimensionsIsNil() {
        XCTAssertNil(Calculator.evaluate("5 km to kg"))
    }

    func testSplitConversion() throws {
        var r = try XCTUnwrap(Calculator.splitConversion("5 km to mi"))
        XCTAssertEqual(r.0, 5)
        XCTAssertEqual(r.1, "km")
        XCTAssertEqual(r.2, "mi")

        r = try XCTUnwrap(Calculator.splitConversion("72 f to c"))
        XCTAssertEqual(r.0, 72)
        XCTAssertEqual(r.1, "f")
        XCTAssertEqual(r.2, "c")

        // número grudado na unidade, sem conector
        r = try XCTUnwrap(Calculator.splitConversion("5km mi"))
        XCTAssertEqual(r.0, 5)
        XCTAssertEqual(r.1, "km")
        XCTAssertEqual(r.2, "mi")

        // vírgula decimal
        r = try XCTUnwrap(Calculator.splitConversion("1,5 gb em mb"))
        XCTAssertEqual(r.0, 1.5)

        // o segundo "in" é a unidade, o primeiro é o conector
        r = try XCTUnwrap(Calculator.splitConversion("10 cm in in"))
        XCTAssertEqual(r.1, "cm")
        XCTAssertEqual(r.2, "in")
    }

    func testSplitConversionRejectsNonConversions() {
        XCTAssertNil(Calculator.splitConversion("5 km"))
        XCTAssertNil(Calculator.splitConversion("km to mi"))
        XCTAssertNil(Calculator.splitConversion("hello"))
    }

    func testCurrencyQuery() throws {
        let r = try XCTUnwrap(Calculator.currencyQuery("100 usd to brl"))
        XCTAssertEqual(r.0, 100)
        XCTAssertEqual(r.1, "USD")
        XCTAssertEqual(r.2, "BRL")

        let c = try XCTUnwrap(Calculator.currencyQuery("1,5 EUR em gbp"))
        XCTAssertEqual(c.0, 1.5)
        XCTAssertEqual(c.1, "EUR")
        XCTAssertEqual(c.2, "GBP")
    }

    func testCurrencyQueryRejectsInvalid() {
        XCTAssertNil(Calculator.currencyQuery("100 usd to usd"))
        XCTAssertNil(Calculator.currencyQuery("100 usd to xyz"))
        XCTAssertNil(Calculator.currencyQuery("100 km to mi"))
        XCTAssertNil(Calculator.currencyQuery("usd"))
    }

    func testNumberAndFormat() {
        XCTAssertEqual(Calculator.number("1,5"), 1.5)
        XCTAssertEqual(Calculator.number("2.25"), 2.25)
        XCTAssertNil(Calculator.number("abc"))
        XCTAssertEqual(Calculator.format(0), "0")
        XCTAssertEqual(Calculator.format(42), "42")
        XCTAssertEqual(Calculator.format(1_000_000), "1000000")   // sem separador de milhar
    }
}
