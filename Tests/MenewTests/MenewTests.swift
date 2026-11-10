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

    func testNotchSkipsCalendarBlocksDismissedAndMutedMeetings() {
        var lunch = meeting("almoço", 0, 60); lunch.title = "Almoço"
        var call = meeting("call", 0, 30); call.link = URL(string: "https://meet.example.com/x")
        var sync = meeting("sync", 0, 30); sync.withOthers = true
        // Sem link nem convidados é bloqueio de agenda
        XCTAssertTrue(MeetingStore.notchIgnores(lunch, dismissed: [], muted: [], onlyReal: true))
        XCTAssertFalse(MeetingStore.notchIgnores(lunch, dismissed: [], muted: [], onlyReal: false))
        XCTAssertFalse(MeetingStore.notchIgnores(call, dismissed: [], muted: [], onlyReal: true))
        XCTAssertFalse(MeetingStore.notchIgnores(sync, dismissed: [], muted: [], onlyReal: true))
        // Silenciado pelo título, sem ligar para acento e maiúsculas
        XCTAssertTrue(MeetingStore.notchIgnores(sync, dismissed: [], muted: ["SYNC"], onlyReal: true))
        XCTAssertTrue(MeetingStore.notchIgnores(lunch, dismissed: [], muted: ["almoco"], onlyReal: false))
        // Dispensado só nesta ocorrência: o mesmo evento em outro horário volta a avisar
        let key = MeetingStore.occurrence(call)
        XCTAssertTrue(MeetingStore.notchIgnores(call, dismissed: [key], muted: [], onlyReal: true))
        var tomorrow = call; tomorrow.start = call.start.addingTimeInterval(86_400)
        XCTAssertFalse(MeetingStore.notchIgnores(tomorrow, dismissed: [key], muted: [], onlyReal: true))
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
        for empty in ["não especificado", "Not specified", "N/A", "-", "nicht angegeben", "未指定", "  ", "sem data", "TBD"] {
            XCTAssertNil(meaningful(empty), empty)
        }
        XCTAssertEqual(meaningful("Ana"), "Ana")
    }

    func testChunksCutBetweenLinesAndKeepEverything() {
        let lines = (1...300).map { "Eu: fala número \($0) sobre o assunto da reunião" }
        let text = lines.joined(separator: "\n")
        let parts = RecordingStore.chunks(text, size: 1000)
        XCTAssertGreaterThan(parts.count, 5)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 1000 })
        // Nada se perde e nenhuma fala é cortada ao meio
        XCTAssertEqual(parts.joined(separator: "\n"), text)
        // Uma fala enorme sem quebra também é dividida
        XCTAssertEqual(RecordingStore.chunks(String(repeating: "a", count: 2500), size: 1000).map(\.count), [1000, 1000, 500])
    }

    func testTopicsFromDifferentPartsAreMerged() {
        var topics: [Recording.Topic] = []
        RecordingStore.mergeTopics(&topics, [("Arquitetura", ["Integração ao Conex foi discutida."]), ("Aspectos jurídicos", ["Proxy pode ter implicações."])])
        RecordingStore.mergeTopics(&topics, [("arquitetura na Tupi", ["Integração ao Conex foi discutida.", "Gateway OCPP como alternativa."]),
                                             ("Vazio", ["não especificado"])])
        XCTAssertEqual(topics.map(\.title), ["Arquitetura", "Aspectos jurídicos"])
        XCTAssertEqual(topics[0].points, ["Integração ao Conex foi discutida.", "Gateway OCPP como alternativa."])
    }

    func testDedupeKeepsTheMoreCompleteVersion() {
        XCTAssertEqual(RecordingStore.dedupe(["Reunião na segunda", "reuniao na segunda, das 11h às 12h", "Outro ponto", "  "]),
                       ["reuniao na segunda, das 11h às 12h", "Outro ponto"])
    }

    func testSameIdeaInOtherWordsIsARepeat() {
        XCTAssertTrue(RecordingStore.similar("Preparar a conta de retorno", "Preparar uma conta simples de retorno"))
        XCTAssertFalse(RecordingStore.similar("Preparar a conta de retorno", "Mandar a planilha do cardápio"))
        XCTAssertTrue(RecordingStore.isSectionTitle("Tarefas"))
        XCTAssertTrue(RecordingStore.isSectionTitle("Próximos passos:"))
        XCTAssertFalse(RecordingStore.isSectionTitle("Tarefas do piloto na loja"))
    }

    func testEmptyDecisionsAreNotDecisions() {
        XCTAssertTrue(RecordingStore.isNonItem("Não foi tomada qualquer decisão formal nesta parte do encontro."))
        XCTAssertTrue(RecordingStore.isNonItem("No decisions were made."))
        XCTAssertFalse(RecordingStore.isNonItem("Foi decidido que a vistoria será feita por vídeo."))
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

// MARK: Monitores (DDC)

final class DDCBlameTests: XCTestCase {
    func testOnlyAMonitorThatDroppedRightAfterDDCIsBlamed() {
        let now = Date()
        let probes: [(id: CGDirectDisplayID, key: String, at: Date)] = [
            (1, "a", now.addingTimeInterval(-2)),   // falou DDC há 2 s e sumiu: culpado
            (2, "b", now.addingTimeInterval(-2)),   // falou DDC há 2 s e continua na tela: outra mudança qualquer
            (3, "c", now.addingTimeInterval(-30)),  // sumiu, mas a conversa foi há muito tempo
        ]
        let blamed = DisplayController.dropped(probes, online: [2, 99], now: now)
        XCTAssertEqual(blamed.map(\.key), ["a"])
        // Reconfiguração sem ninguém sumir (resolução, outro monitor entrando, acordar): ninguém é culpado
        XCTAssertTrue(DisplayController.dropped(probes, online: [1, 2, 3], now: now).isEmpty)
    }
}

// MARK: Brilho acompanhando a tela do Mac

final class FollowBrightnessTests: XCTestCase {
    func testMonitorFollowsTheMacDisplayWithItsOwnOffset() {
        XCTAssertEqual(DisplayController.followed(builtin: 0.6, offset: 0), 0.6, accuracy: 0.0001)
        // Deixado 20% mais claro: segue a tela, sempre 20% acima
        XCTAssertEqual(DisplayController.followed(builtin: 0.5, offset: 0.2), 0.7, accuracy: 0.0001)
        // Nunca passa de 100% nem de 0%
        XCTAssertEqual(DisplayController.followed(builtin: 0.95, offset: 0.2), 1, accuracy: 0.0001)
        XCTAssertEqual(DisplayController.followed(builtin: 0.1, offset: -0.3), 0, accuracy: 0.0001)
    }

    func testLowLightDimsTheImageBeyondTheBacklight() {
        // Com luz normal, só a luz do monitor muda
        let normal = DisplayController.followedParts(builtin: 0.6, offset: 0)
        XCTAssertEqual(normal.backlight, 0.6, accuracy: 0.0001)
        XCTAssertEqual(normal.image, 1, accuracy: 0.0001)
        // Com pouca luz, a imagem também escurece, até o mínimo com a tela do Mac em 0
        let dim = DisplayController.followedParts(builtin: 0.125, offset: 0)
        XCTAssertEqual(dim.backlight, 0.125, accuracy: 0.0001)
        XCTAssertEqual(dim.image, 0.5, accuracy: 0.0001)
        XCTAssertEqual(DisplayController.followedParts(builtin: 0, offset: 0).image, 0, accuracy: 0.0001)
    }
}
