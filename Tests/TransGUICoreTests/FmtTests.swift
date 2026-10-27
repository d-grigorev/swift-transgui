import Foundation
import Testing
import TransGUICore

/// Size/speed/ETA/ratio formatting. Includes the regression case for the
/// unit label that once ran one step ahead of the value (7.1 GB shown as TB).
@Suite("Fmt formatting")
struct FmtTests {
    @Test("Byte and unit boundaries")
    func sizes() {
        #expect(Fmt.size(Int64(0)) == "0 b")
        #expect(Fmt.size(Int64(512)) == "512 b")
        #expect(Fmt.size(Int64(1023)) == "1023 b")
        #expect(Fmt.size(Int64(1024)) == "1.0 KB")
        #expect(Fmt.size(Int64(1536)) == "1.5 KB")
        #expect(Fmt.size(Int64(1_572_864)) == "1.5 MB")
        #expect(Fmt.size(Int64(1_610_612_736)) == "1.5 GB")
        // Regression: this used to print "7.0 TB".
        #expect(Fmt.size(Int64(7_516_192_768)) == "7.0 GB")
        #expect(Fmt.size(Int64(1_099_511_627_776)) == "1.0 TB")
    }

    @Test("Unknown and negative values")
    func optionalSizes() {
        #expect(Fmt.size(nil as Int64?) == "?")
        #expect(Fmt.size(Int64(-1)) == "?")
    }

    @Test("Speeds render blank at zero")
    func speeds() {
        #expect(Fmt.speed(Int64(0)) == nil)
        #expect(Fmt.speed(Int64(1_572_864)) == "1.5 MB/s")
        #expect(Fmt.speedLimit(kilobytesPerSecond: nil) == "Unlimited")
        #expect(Fmt.speedLimit(kilobytesPerSecond: 0) == "Unlimited")
        #expect(Fmt.speedLimit(kilobytesPerSecond: 100) == "100 KB")
    }

    @Test("ETA rounding and units")
    func etas() {
        #expect(Fmt.eta(nil) == nil)
        #expect(Fmt.eta(0) == nil)
        #expect(Fmt.eta(-1) == nil)
        #expect(Fmt.eta(12) == "12s")
        #expect(Fmt.eta(45) == "45s")
        #expect(Fmt.eta(120) == "2m")
        #expect(Fmt.eta(3660) == "1h")  // >30 min: rounded to 5 min steps
        #expect(Fmt.eta(4000) == "1h, 5m")  // 4000 s → 3900 s (5 min steps)
        #expect(Fmt.eta(10_000) == "3h")  // >2 h: rounded to 1 h steps
        #expect(Fmt.eta(90_000) == "1d, 1h")
    }

    @Test("Ratio formatting")
    func ratios() {
        #expect(Fmt.ratio(nil) == "")
        #expect(Fmt.ratio(-1) == "")
        #expect(Fmt.ratio(0) == "0.000")
        #expect(Fmt.ratio(1.5) == "1.500")
        #expect(Fmt.ratio(.infinity) == "∞")
        #expect(Fmt.ratio(2_000_000) == "∞")
    }

    @Test("Percent and duration")
    func percentAndDuration() {
        #expect(Fmt.percent(0) == "0.0%")
        #expect(Fmt.percent(0.453) == "45.3%")
        #expect(Fmt.percent(1) == "100.0%")
        #expect(Fmt.percent(2) == "100.0%")  // clamped
        #expect(Fmt.duration(nil) == "-")
        #expect(Fmt.duration(0) == "-")
        #expect(Fmt.duration(3660) == "1h, 1m")
        #expect(Fmt.duration(90_000) == "1d, 1h")
    }

    @Test("Relative times")
    func relativeTimes() {
        let now = Date().timeIntervalSince1970
        #expect(Fmt.relativeTime(unix: 0) == "-")
        #expect(Fmt.relativeTime(unix: now - 30) == "just now")
        #expect(Fmt.relativeTime(unix: now - 1200) == "20m")
        #expect(Fmt.relativeTime(unix: now - (3 * 86400 + 5 * 3600)) == "3d, 5h")
        #expect(Fmt.relativeTime(unix: now - (2 * 86400 + 1 * 3600)) == "2d, 1h")
    }
}
