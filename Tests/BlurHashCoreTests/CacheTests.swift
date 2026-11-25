import BlurHashCore
import Testing

@MainActor
@Suite struct CacheTests {
  func key(_ index: Int) -> BlurHashKey { BlurHashKey(hash: "hash\(index)", width: 32, height: 32) }

  @Test func makesAValueOncePerKey() {
    let cache = BlurHashCache<Int>()
    var made = 0
    for _ in 0..<5 {
      let value = cache.value(for: key(1)) {
        made += 1
        return 42
      }
      #expect(value == 42)
    }
    #expect(made == 1)
    #expect(cache.count == 1)
  }

  @Test func doesNotKeepMissingValues() {
    let cache = BlurHashCache<Int>()
    var made = 0
    for _ in 0..<3 {
      #expect(cache.value(for: key(1)) {
        made += 1
        return nil
      } == nil)
    }
    #expect(made == 3)
    #expect(cache.count == 0)
  }

  @Test func sizeAndPunchArePartOfTheKey() {
    let cache = BlurHashCache<String>()
    cache.insert("a", for: BlurHashKey(hash: "h", width: 16, height: 16))
    cache.insert("b", for: BlurHashKey(hash: "h", width: 32, height: 32))
    cache.insert("c", for: BlurHashKey(hash: "h", width: 32, height: 32, punch: 2))
    #expect(cache.count == 3)
    #expect(cache.value(for: BlurHashKey(hash: "h", width: 32, height: 32)) == "b")
  }

  @Test func evictsTheLeastRecentlyUsed() {
    let cache = BlurHashCache<Int>(countLimit: 8)
    for index in 0..<8 { cache.insert(index, for: key(index)) }
    // Touch the first two, so the next insertion evicts among the others.
    _ = cache.value(for: key(0))
    _ = cache.value(for: key(1))
    cache.insert(8, for: key(8))
    #expect(cache.count == 6)
    #expect(cache.value(for: key(0)) == 0)
    #expect(cache.value(for: key(1)) == 1)
    #expect(cache.value(for: key(8)) == 8)
    #expect(cache.value(for: key(2)) == nil)
  }

  @Test func loweringTheLimitEvictsAtOnce() {
    let cache = BlurHashCache<Int>(countLimit: 100)
    for index in 0..<100 { cache.insert(index, for: key(index)) }
    cache.countLimit = 10
    #expect(cache.count <= 10)
    #expect(cache.value(for: key(99)) == 99)
    cache.countLimit = 0
    #expect(cache.count == 0)
    cache.removeAll()
    #expect(cache.count == 0)
  }
}
