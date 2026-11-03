import SwiftUI
import XCTest
@testable import Menew

// Testes da lógica pura: nada de tela, rede, arquivos do usuário ou permissões.
// Rodam com `swift test` e em todo pull request (.github/workflows/ci.yml).

// MARK: Senhas

final class SecretFieldTests: XCTestCase {
    func testParseKeepsTitleAndFields() {
        let (title, fields) = SecretField.parse("Banco\nUsuário: ana\nSenha: a:b:c\n\nPIN:")
        XCTAssertEqual(title, "Banco")
        XCTAssertEqual(fields.map(\.key), ["Usuário", "Senha", "PIN"])
        // Só o primeiro ":" separa: senhas com ":" continuam inteiras
        XCTAssertEqual(fields.map(\.value), ["ana", "a:b:c", ""])
    }

    func testFormatRoundTrip() {
        let fields = [SecretField(key: "Usuário", value: "ana"), SecretField(key: "Senha", value: "x y")]
        let (title, parsed) = SecretField.parse(SecretField.format(title: "Wi-Fi", fields: fields))
        XCTAssertEqual(title, "Wi-Fi")
        XCTAssertEqual(parsed.map(\.key), ["Usuário", "Senha"])
        XCTAssertEqual(parsed.map(\.value), ["ana", "x y"])
    }

    @MainActor
    func testPicksPasswordAndUsernameInAnyLanguage() {
        func f(_ pairs: [(String, String)]) -> [SecretField] { pairs.map { SecretField(key: $0.0, value: $0.1) } }
        let cases: [([SecretField], String?, String?)] = [
            (f([("Usuário", "ana@x.com"), ("Senha", "s3nha")]), "s3nha", "ana@x.com"),
            (f([("Username", "ana"), ("Password", "pw1")]), "pw1", "ana"),
            (f([("Benutzer", "ana"), ("Passwort", "pw2")]), "pw2", "ana"),
            (f([("Usuario", "ana"), ("Contraseña", "pw3")]), "pw3", "ana"),
            // Sem nomes conhecidos: senha é o último campo, usuário o primeiro
            (f([("a", "first"), ("b", "last")]), "last", "first"),
            // Um campo só: não inventa usuário
            (f([("PIN", "1234")]), "1234", nil),
        ]
        for (fields, password, username) in cases {
            XCTAssertEqual(ClipboardManager.secretValue(fields, username: false), password, "\(fields.map(\.key))")
            XCTAssertEqual(ClipboardManager.secretValue(fields, username: true), username, "\(fields.map(\.key))")
        }
    }
}

// MARK: Bateria

@MainActor
final class BatteryWearTests: XCTestCase {
    private func battery(_ p: Int, _ ac: Bool) -> BatteryInfo { BatteryInfo(percent: p, charging: ac, onAC: ac, minutesLeft: nil) }
    private func health(_ t: Double) -> BatteryHealth { BatteryHealth(cycles: 7, healthPercent: 100, temperature: t) }

    func testCountsCyclesHoursHeatFullAndLow() throws {
        let wear = BatteryWear()  // sem load: nada é gravado em disco
        var t = try XCTUnwrap(Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()))
        // 14h: 60 min fora da tomada, de 100% a 70%, a 36 °C
        for i in 0...60 { wear.record(battery(100 - i / 2, false), health(36), now: t); t += 60 }
        // Duas horas dormindo: a carga que caiu conta, o tempo parado não vira minutos
        t += 7200
        wear.record(battery(15, false), health(30), now: t)
        // Tomada até 100% e mais 90 min cheia
        for p in stride(from: 16, through: 100, by: 4) { t += 60; wear.record(battery(p, true), health(30), now: t) }
        for _ in 0..<90 { t += 60; wear.record(battery(100, true), health(30), now: t) }
        // Leituras a cada 2 s não contam em dobro
        for _ in 0..<20 { t += 2; wear.record(battery(100, true), health(30), now: t) }

        let day = try XCTUnwrap(wear.days.last)
        XCTAssertEqual(day.used, 85)
        XCTAssertEqual(day.cycles, 0.85, accuracy: 0.001)
        XCTAssertEqual(day.hot, 60)
        XCTAssertEqual(day.full, 92)
        XCTAssertEqual(day.low, 1)
        XCTAssertEqual(day.hours[14], 29)
        XCTAssertEqual(wear.summary(now: t).peakHour, 17)
    }

    func testNoDataMeansNoSummary() {
        let s = BatteryWear().summary()
        XCTAssertEqual(s.daysWithData, 0)
        XCTAssertEqual(s.week, 0)
        XCTAssertNil(s.peakHour)
    }
}

// MARK: Reuniões e notch

@MainActor
final class MeetingTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func meeting(_ id: String, _ startMin: Double, _ endMin: Double) -> Meeting {
        Meeting(id: id, title: id, start: t0.addingTimeInterval(startMin * 60), end: t0.addingTimeInterval(endMin * 60), link: nil, color: .blue)
    }

    func testBackToBackMeetingsSwitchTwoMinutesBeforeTheEnd() {
        let list = [meeting("foco", -60, 0), meeting("wemob", 0, 30)]
        func current(at minutes: Double) -> String? {
            let now = t0.addingTimeInterval(minutes * 60)
            return MeetingStore.current(list.filter { $0.end > now }, now: now)?.title
        }
        XCTAssertEqual(current(at: -5), "foco")
        XCTAssertEqual(current(at: -1.5), "wemob")
        XCTAssertEqual(current(at: 0.1), "wemob")
    }

    func testMeetingWithAGapStaysUntilItEnds() {
        let list = [meeting("a", -60, 0), meeting("b", 30, 60)]
        let now = t0.addingTimeInterval(-60)
        XCTAssertEqual(MeetingStore.current(list, now: now)?.title, "a")
    }

    func testNotchMeetingCardLeavesOnceYouJoin() {
        let m = meeting("x", 0, 30)
        XCTAssertTrue(NotchCenter.showsMeeting(m, now: t0.addingTimeInterval(-60), inCall: false, joined: false))
        XCTAssertTrue(NotchCenter.showsMeeting(m, now: t0.addingTimeInterval(10), inCall: false, joined: false))
        XCTAssertFalse(NotchCenter.showsMeeting(m, now: t0.addingTimeInterval(10), inCall: true, joined: false))
        XCTAssertFalse(NotchCenter.showsMeeting(m, now: t0.addingTimeInterval(65), inCall: false, joined: false))
        XCTAssertFalse(NotchCenter.showsMeeting(m, now: t0.addingTimeInterval(-60), inCall: false, joined: true))
        // Longe demais do início ainda não aparece
        XCTAssertFalse(NotchCenter.showsMeeting(m, now: t0.addingTimeInterval(-3600), inCall: false, joined: false))
    }
}

// MARK: Gravações

@MainActor
final class RecordingMinutesTests: XCTestCase {
    func testShortRecordingGetsATitleAndNoInventedMinutes() async throws {
        let result = await RecordingStore.minutes("Eu: Teste testando 12 som teste.")
        let m = try XCTUnwrap(result)
        XCTAssertEqual(m.title, "Teste testando 12 som teste")
        XCTAssertTrue(m.summary.isEmpty)
        XCTAssertTrue(m.tasks.isEmpty)
        XCTAssertTrue(m.decisions.isEmpty)
    }

    func testPlaceholderAnswersAreDropped() {
        for empty in ["não especificado", "Not specified", "N/A", "-", "nicht angegeben", "未指定", "  "] {
            XCTAssertNil(meaningful(empty), empty)
        }
        XCTAssertEqual(meaningful("Ana"), "Ana")
    }

    func testClock() {
        XCTAssertEqual(RecordingStore.clock(65), "1:05")
        XCTAssertEqual(RecordingStore.clock(3725), "1:02:05")
    }
}

// MARK: Busca

@MainActor
final class SearchTests: XCTestCase {
    func testFoldIgnoresAccentsAndCase() {
        XCTAssertEqual(PaletteSearch.fold("Reunião ÀS 9h"), PaletteSearch.fold("reuniao as 9h"))
    }

    func testTokensSplitCamelCaseAndDropShortWords() {
        XCTAssertEqual(SmartClipSearch.tokens("swiftCharts é ótimo"), ["swift", "charts", "otimo"])
    }

    func testSameRoot() {
        XCTAssertTrue(SmartClipSearch.sameRoot("erro", "error"))
        XCTAssertTrue(SmartClipSearch.sameRoot("compilacao", "compile"))
        XCTAssertFalse(SmartClipSearch.sameRoot("cat", "car"))
    }
}
