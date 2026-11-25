/// What a decoded image is cached under: the hash and the parameters of ``BlurHash/decode(_:width:height:punch:)``.
public struct BlurHashKey: Hashable, Sendable {
  public let hash: String
  public let width: Int
  public let height: Int
  public let punch: Double

  public init(hash: String, width: Int, height: Int, punch: Double = 1) {
    self.hash = hash
    self.width = width
    self.height = height
    self.punch = punch
  }
}

/// A cache of what is made from decoded hashes (the pixels, or a platform image made from them), keyed by hash and size,
/// so a hash is decoded once however many views show it.
///
/// It keeps at most `countLimit` values; past that, the least recently used quarter goes. It belongs to the main actor,
/// as the views that read it do.
@MainActor
public final class BlurHashCache<Value> {
  private struct Entry {
    var value: Value
    var lastUse: Int
  }

  private var entries: [BlurHashKey: Entry] = [:]
  private var clock = 0

  /// The most values kept. Lowering it evicts at once.
  public var countLimit: Int {
    didSet { trim() }
  }

  public init(countLimit: Int = 256) {
    self.countLimit = countLimit
  }

  /// The number of values in the cache.
  public var count: Int { entries.count }

  /// The value for `key`, or nil.
  public func value(for key: BlurHashKey) -> Value? {
    guard var entry = entries[key] else { return nil }
    clock += 1
    entry.lastUse = clock
    entries[key] = entry
    return entry.value
  }

  /// The value for `key`, made by `make` and kept when it is missing. A nil from `make` is not kept.
  public func value(for key: BlurHashKey, orMake make: () -> Value?) -> Value? {
    if let value = value(for: key) { return value }
    guard let value = make() else { return nil }
    insert(value, for: key)
    return value
  }

  /// Keeps `value` for `key`, replacing what was there.
  public func insert(_ value: Value, for key: BlurHashKey) {
    clock += 1
    entries[key] = Entry(value: value, lastUse: clock)
    trim()
  }

  /// Forgets every value.
  public func removeAll() {
    entries.removeAll()
  }

  private func trim() {
    guard entries.count > max(0, countLimit) else { return }
    // Evict down to three quarters of the limit at once, so a full cache does not sort on every insertion.
    let keep = max(0, countLimit) * 3 / 4
    guard keep > 0 else {
      entries.removeAll()
      return
    }
    var uses: [Int] = []
    uses.reserveCapacity(entries.count)
    for entry in entries.values { uses.append(entry.lastUse) }
    uses.sort()
    let cutoff = uses[uses.count - keep]
    var kept: [BlurHashKey: Entry] = [:]
    kept.reserveCapacity(keep)
    for (key, entry) in entries where entry.lastUse >= cutoff { kept[key] = entry }
    entries = kept
  }
}
