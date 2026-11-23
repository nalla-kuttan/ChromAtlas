import Foundation

/// Columnar, allocation-light in-memory index for sub-16 ms cross-filtering of 100k+ assets.
/// SQLite is the durable store; this is rebuilt from it whenever the asset set changes.
struct QueryEngine: Sendable {
    struct Result: Sendable {
        /// Indices matching every filter, best colour match first.
        var matches: [Int32] = []
        /// Indices matching non-colour filters (time/geo/season/solar) — drives wheel density.
        var base: [Int32] = []
        /// Hue × saturation histogram of `base`, for the wheel's density overlay.
        var density: [Float] = Array(repeating: 0, count: QueryEngine.hueBins * QueryEngine.satBins)
        var maxDensity: Float = 0
        var matchingCities: Set<Int> = []
        var matchingTrips: Set<Int> = []
        var elapsedMs: Double = 0
    }

    static let hueBins = 36
    static let satBins = 5
    static let minAccentWeight: Float = 0.06   // small vivid accents (≥ 6% of pixels) stay discoverable

    private(set) var count = 0
    private var ts: [Double] = []
    private var hue: [Float] = []      // 3 per asset
    private var chroma: [Float] = []
    private var light: [Float] = []
    private var weight: [Float] = []
    private var meanL: [Float] = []
    private var season: [Int8] = []
    private var phase: [Int8] = []     // -1 = unknown
    private var city: [Int32] = []     // -1 = unknown
    private var country: [Int16] = []    // -1 = unknown
    private var countryIndex: [String: Int16] = [:]
    private var trip: [Int32] = []
    private var maxCityID = 0
    private var maxTripID = 0

    init() {}

    init(_ assets: [AssetRecord]) {
        count = assets.count
        ts.reserveCapacity(count)
        hue.reserveCapacity(count * 3); chroma.reserveCapacity(count * 3)
        light.reserveCapacity(count * 3); weight.reserveCapacity(count * 3)
        for a in assets {
            ts.append(a.timestamp)
            var mL: Float = 0
            for k in 0..<3 {
                if k < a.colors.count {
                    let c = a.colors[k]
                    hue.append(Float(c.lab.hueDegrees)); chroma.append(Float(c.lab.chroma))
                    light.append(Float(c.lab.L)); weight.append(Float(c.weight))
                    mL += Float(c.lab.L * c.weight)
                } else {
                    hue.append(0); chroma.append(0); light.append(0); weight.append(0)
                }
            }
            meanL.append(mL)
            season.append(Int8(a.season.rawValue))
            phase.append(Int8(a.solarPhase?.rawValue ?? -1))
            city.append(Int32(a.cityID ?? -1))
            if let cc = a.countryCode {
                if countryIndex[cc] == nil { countryIndex[cc] = Int16(countryIndex.count) }
                country.append(countryIndex[cc]!)
            } else {
                country.append(-1)
            }
            trip.append(Int32(a.tripID ?? -1))
            maxCityID = max(maxCityID, a.cityID ?? 0)
            maxTripID = max(maxTripID, a.tripID ?? 0)
        }
    }

    func run(_ f: FilterState) -> Result {
        let t0 = CFAbsoluteTimeGetCurrent()
        var r = Result()
        r.base.reserveCapacity(count)
        let seasonMask = f.seasons.reduce(0) { $0 | (1 << $1.rawValue) }
        let phaseMask = f.phases.reduce(0) { $0 | (1 << $1.rawValue) }
        let windows = f.hueWindows
        let winCount = windows.count
        let w0c = Float(windows.first?.0 ?? 0), w0h = Float(windows.first?.1 ?? 1)
        let w1c = Float(windows.count > 1 ? windows[1].0 : 0), w1h = Float(windows.count > 1 ? windows[1].1 : 1)
        let mono = f.color != nil && f.effectiveHarmony == .monochrome
        let targetC = Float(f.color?.targetChroma ?? 0)
        let chromaTol = 0.035 + targetC * 0.3
        let lLo = Float(f.luminance.lowerBound), lHi = Float(f.luminance.upperBound)
        let lumActive = f.luminance != 0...1
        let colorActive = f.color != nil
        let scoring = colorActive || lumActive
        let hasTime = f.timeRange != nil
        let tLo = f.timeRange?.lowerBound ?? 0, tHi = f.timeRange?.upperBound ?? 0
        let cityF = Int32(f.cityID ?? -2), tripF = Int32(f.tripID ?? -2)
        let countryF: Int16 = f.countryCode.map { countryIndex[$0] ?? -3 } ?? -2
        let minW = QueryEngine.minAccentWeight
        let satScale = Float(QueryEngine.satBins) / Float(ColorSelection.maxChroma)
        var scored: [(Int32, Float)] = []
        if scoring { scored.reserveCapacity(count / 4) }
        var density = [Float](repeating: 0, count: QueryEngine.hueBins * QueryEngine.satBins)

        ts.withUnsafeBufferPointer { ts in
        hue.withUnsafeBufferPointer { hue in
        chroma.withUnsafeBufferPointer { chroma in
        light.withUnsafeBufferPointer { light in
        weight.withUnsafeBufferPointer { weight in
        season.withUnsafeBufferPointer { season in
        phase.withUnsafeBufferPointer { phase in
        city.withUnsafeBufferPointer { city in
        country.withUnsafeBufferPointer { country in
        trip.withUnsafeBufferPointer { trip in
        density.withUnsafeMutableBufferPointer { dens in
            for i in 0..<count {
                if hasTime, ts[i] < tLo || ts[i] > tHi { continue }
                if seasonMask != 0, seasonMask & (1 << Int(season[i])) == 0 { continue }
                if phaseMask != 0 { let p = phase[i]; if p < 0 || phaseMask & (1 << Int(p)) == 0 { continue } }
                if cityF != -2, city[i] != cityF { continue }
                if countryF != -2, country[i] != countryF { continue }
                if tripF != -2, trip[i] != tripF { continue }
                r.base.append(Int32(i))

                var best: Float = -1
                let o = i * 3
                for k in o..<(o + 3) {
                    let w = weight[k]
                    if w < minW { continue }
                    let c = chroma[k]
                    let h = hue[k]
                    // Density histogram over every meaningful centroid.
                    let sb = min(QueryEngine.satBins - 1, Int(c * satScale))
                    let hb = min(QueryEngine.hueBins - 1, Int(h * 0.1))
                    dens[sb &* QueryEngine.hueBins &+ hb] += w

                    guard scoring else { continue }
                    if lumActive { let L = light[k]; if L < lLo || L > lHi { continue } }
                    var s = w
                    if colorActive {
                        if mono {
                            if c >= 0.045 { continue }
                        } else {
                            if c <= 0.03 || abs(c - targetC) > chromaTol { continue }
                            var d = abs(h - w0c); if d > 180 { d = 360 - d }
                            var hs: Float = d <= w0h ? 1 - 0.6 * d / w0h : -1
                            if winCount > 1 {
                                var d1 = abs(h - w1c); if d1 > 180 { d1 = 360 - d1 }
                                if d1 <= w1h { hs = max(hs, 1 - 0.6 * d1 / w1h) }
                            }
                            if hs <= 0 { continue }
                            s = w * hs
                        }
                    }
                    if s > best { best = s }
                }
                if scoring, best > 0 { scored.append((Int32(i), best)) }
            }
        }}}}}}}}}}}
        r.density = density

        if scoring {
            scored.sort { $0.1 > $1.1 }
            r.matches = scored.map(\.0)
        } else {
            r.matches = r.base.reversed()   // assets are time-sorted: newest first
        }
        var seenCity = [Bool](repeating: false, count: maxCityID + 1)
        var seenTrip = [Bool](repeating: false, count: maxTripID + 1)
        for i in r.matches {
            let c = Int(city[Int(i)]); if c >= 0, !seenCity[c] { seenCity[c] = true; r.matchingCities.insert(c) }
            let t = Int(trip[Int(i)]); if t >= 0, !seenTrip[t] { seenTrip[t] = true; r.matchingTrips.insert(t) }
        }
        r.maxDensity = r.density.max() ?? 0
        r.elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return r
    }
}
