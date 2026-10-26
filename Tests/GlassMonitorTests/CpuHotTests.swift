import Testing
@testable import GlassMonitor

@Suite struct CpuHot {
    /// Feeds samples one by one, as `Monitor.refresh` does every 1.5 s.
    private func run(_ samples: [(load: Double, temp: Double?)], from hot: Bool = false) -> [Bool] {
        var state = (hot: hot, streak: 0)
        return samples.map { s in
            state = Monitor.nextHot(state.hot, streak: state.streak, load: s.load, temp: s.temp)
            return state.hot
        }
    }

    @Test func turnsHotAfterThreeSamples() {
        #expect(run([(0.9, 60), (0.9, 60), (0.9, 60)]) == [false, false, true])
        #expect(run([(0.3, 97), (0.3, 97), (0.3, 97)]) == [false, false, true])
    }

    @Test func intelIdleTemperatureIsNotHot() {
        #expect(run([(0.3, 90), (0.3, 90), (0.3, 90), (0.3, 90)]) == [false, false, false, false])
    }

    @Test func shortSpikeIsIgnored() {
        #expect(run([(0.9, 60), (0.9, 60), (0.2, 50), (0.9, 60), (0.9, 60)]) == [false, false, false, false, false])
    }

    @Test func noTemperatureSensorStillUsesLoad() {
        #expect(run([(0.9, nil), (0.9, nil), (0.9, nil)]) == [false, false, true])
        #expect(run([(0.5, nil), (0.5, nil), (0.5, nil)]) == [false, false, false])
    }

    @Test func staysHotInTheGapBetweenThresholds() {
        #expect(run([(0.8, 88), (0.8, 88), (0.8, 88), (0.8, 88)], from: true) == [true, true, true, true])
    }

    @Test func coolsDownAfterThreeQuietSamples() {
        #expect(run([(0.3, 60), (0.3, 60), (0.3, 60)], from: true) == [true, true, false])
    }

    @Test func aHotSampleRestartsTheCooldown() {
        #expect(run([(0.3, 60), (0.3, 60), (0.8, 60), (0.3, 60), (0.3, 60), (0.3, 60)], from: true)
                == [true, true, true, true, true, false])
    }
}
