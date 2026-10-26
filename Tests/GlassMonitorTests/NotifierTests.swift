import Testing
@testable import GlassMonitor

@Suite struct NotifierThresholds {
    let reset = 29_000_000   // minutes since 1970

    @Test func firstRunIsSilent() {
        let r = Notifier.decide(percent: 55, reset: reset, prevReset: nil, fired: [])
        #expect(r.announce == nil)
        #expect(r.fired == [20, 40])
    }

    @Test func crossingAThresholdAnnouncesIt() {
        let r = Notifier.decide(percent: 41, reset: reset, prevReset: reset, fired: [20])
        #expect(r.announce == 40)
        #expect(r.fired == [20, 40])
    }

    @Test func jumpOverSeveralAnnouncesOnlyTheHighest() {
        let r = Notifier.decide(percent: 85, reset: reset, prevReset: reset, fired: [20])
        #expect(r.announce == 80)
        #expect(r.fired == [20, 40, 80])
    }

    @Test func alreadyAnnouncedStaysQuiet() {
        let r = Notifier.decide(percent: 90, reset: reset, prevReset: reset, fired: [20, 40, 80])
        #expect(r.announce == nil)
    }

    @Test func resetJitterIsTheSameWindow() {
        let r = Notifier.decide(percent: 45, reset: reset + 10, prevReset: reset, fired: [20])
        #expect(r.announce == 40)
    }

    @Test func newWindowStartsOverSilently() {
        let r = Notifier.decide(percent: 45, reset: reset + 300, prevReset: reset, fired: [20, 40, 80])
        #expect(r.announce == nil)
        #expect(r.fired == [20, 40])
    }
}
