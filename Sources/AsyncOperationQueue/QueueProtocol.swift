import Foundation

public protocol QueueProtocol {
  associatedtype Item
  associatedtype ItemHandle
  func start() -> Task<Void, Never>
  func add(item: Item, id: QueueItemId) -> ItemHandle?
}

public struct QueueItemId: Hashable {
  public let id = UUID()
}
