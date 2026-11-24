import XCTest
@testable import Menew

// "A condição precisa durar X min" e rearmar quando ela passa. Usa o `now` injetável e um SystemMonitor sem start().

@MainActor
final class AlertRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var store: AlertRules!
    private var monitor: SystemMonitor!

    override func setUp() {
        super.setUp()
        store = AlertRules()
        monitor = SystemMonitor()
    }

    override func tearDown() {
        store.rules = []   // o didSet grava em UserDefaults: deixa vazio
        UserDefaults.standard.removeObject(forKey: AlertRules.key)
        super.tearDown()
    }

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testFiresOnlyAfterTheConditionHeldForTheDuration() {
        store.rules = [AlertRule(metric: .cpu, above: true, threshold: 80, minutes: 10)]
        monitor.cpu = 0.9
        store.check(monitor, now: t0)
        XCTAssertTrue(store.firedRules().isEmpty)
        store.check(monitor, now: at(9.9))
        XCTAssertTrue(store.firedRules().isEmpty)
        store.check(monitor, now: at(10))
        XCTAssertEqual(store.firedRules().count, 1)
    }

    func testClearingTheConditionResetsTheTimer() {
        store.rules = [AlertRule(metric: .cpu, above: true, threshold: 80, minutes: 10)]
        monitor.cpu = 0.9
        store.check(monitor, now: t0)
        store.check(monitor, now: at(10))
        XCTAssertEqual(store.firedRules().count, 1)

        monitor.cpu = 0.5
        store.check(monitor, now: at(11))
        XCTAssertTrue(store.firedRules().isEmpty)

        // Volta a subir: conta de novo desde o início
        monitor.cpu = 0.9
        store.check(monitor, now: at(12))
        store.check(monitor, now: at(21))
        XCTAssertTrue(store.firedRules().isEmpty)
        store.check(monitor, now: at(22))
        XCTAssertEqual(store.firedRules().count, 1)
    }

    func testInterruptionBeforeTheDurationNeverFires() {
        store.rules = [AlertRule(metric: .cpu, above: true, threshold: 80, minutes: 10)]
        monitor.cpu = 0.9
        store.check(monitor, now: t0)
        monitor.cpu = 0.1
        store.check(monitor, now: at(5))
        monitor.cpu = 0.9
        store.check(monitor, now: at(6))
        store.check(monitor, now: at(12))   // só 6 min seguidos desde que voltou
        XCTAssertTrue(store.firedRules().isEmpty)
    }

    func testZeroMinutesFiresImmediatelyAndBelowThreshold() {
        store.rules = [AlertRule(metric: .cpu, above: false, threshold: 20, minutes: 0)]
        monitor.cpu = 0.5
        store.check(monitor, now: t0)
        XCTAssertTrue(store.firedRules().isEmpty)
        monitor.cpu = 0.1
        store.check(monitor, now: t0)
        XCTAssertEqual(store.firedRules().count, 1)
    }

    func testDisabledRuleNeverFires() {
        store.rules = [AlertRule(metric: .cpu, above: true, threshold: 80, minutes: 0, enabled: false)]
        monitor.cpu = 0.9
        store.check(monitor, now: t0)
        XCTAssertTrue(store.firedRules().isEmpty)
    }

    func testMissingValueIsSkipped() {
        store.rules = [AlertRule(metric: .battery, above: false, threshold: 30, minutes: 0)]
        monitor.battery = nil
        store.check(monitor, now: t0)
        XCTAssertTrue(store.firedRules().isEmpty)
    }
}
