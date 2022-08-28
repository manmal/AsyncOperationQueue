import Foundation

public struct Queue<Item, ItemProgress: ItemProgressProtocol>: QueueProtocol {
  public var _start: () -> Task<Void, Never>
  public var _add: (Item, QueueItemId) -> ItemHandle?

  public func start() -> Task<Void, Never> {
    _start()
  }

  public func add(item: Item, id: QueueItemId) -> ItemHandle? {
    _add(item, id)
  }
}

public protocol ActionProtocol {
  associatedtype Item
  static func startAction() -> Self
  static func stopAction() -> Self
  static func addItemAction(_ item: Item, _ id: QueueItemId) -> Self
}

public protocol ItemHandleProtocol {
  associatedtype ItemProgress: ItemProgressProtocol
  var cancel: () -> Void { get }
  var progressStream: AsyncStream<ItemProgress> { get }
}

public protocol ItemProgressProtocol {
  associatedtype Item
  var itemId: QueueItemId { get }
  var item: Item { get }
}

public extension Queue {
  struct State {
    public var enqueuedItems: [ItemAndId]
    public var executingItems: [ItemAndId]
    public var concurrentExecutions: Int
    public var sendItemProgress: SendItemProgress
    public var isStarted = false

    public init(
      items: [ItemAndId] = [],
      concurrentExecutions: Int = 1
    ) {
      enqueuedItems = items
      executingItems = []
      self.concurrentExecutions = concurrentExecutions
      sendItemProgress = SendItemProgress()
    }

    public struct ItemAndId: Equatable {
      public let id: QueueItemId
      public let item: Item

      public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
      }
    }
  }

  enum Action: ActionProtocol {
    case startQueue
    case stopQueue
    case addRequest(Item, QueueItemId)
    case onWillAdd(Item, QueueItemId)
    case onDidAdd(State.ItemAndId)
    case onNextItemsShouldBeExecuted
    case executeItem(State.ItemAndId)
    case onItemProgress(Item, QueueItemId, ItemProgress)
    case onItemTaskFinished(Item, QueueItemId)
    case onItemTerminationConfirmed(QueueItemId)

    public static func startAction() -> Self { .startQueue }
    public static func stopAction() -> Self { .stopQueue }
    public static func addItemAction(_ item: Item, _ id: QueueItemId) -> Self {
      .addRequest(item, id)
    }
  }

  static func reducer(
    executeItem: @escaping (Item, QueueItemId, Send<Action>) async -> Void,
    sendItemProgress: ((
      Item,
      QueueItemId,
      ItemProgress,
      inout State
    ) -> Void)?
  ) -> Reducer<State, Action, Void> {
    Reducer { state, action, _ in
      switch action {
      case let .addRequest(item, id):
        return .value(.onWillAdd(item, id))

      case let .onWillAdd(item, id):
        let itemAndId = State.ItemAndId(id: id, item: item)
        state.enqueuedItems.append(itemAndId)
        return .value(.onDidAdd(itemAndId))

      case .onDidAdd:
        return .value(.onNextItemsShouldBeExecuted)

      case .onNextItemsShouldBeExecuted:
        guard state.isStarted else { return .none }
        let itemsToExecute = Array(
          state.enqueuedItems
            .prefix(state.concurrentExecutions - state.executingItems.count)
        )
        guard !itemsToExecute.isEmpty else { return .none }
        state.enqueuedItems.removeFirst(itemsToExecute.count)
        state.executingItems.append(contentsOf: itemsToExecute)
        return .run { send in
          for itemAndId in itemsToExecute {
            send(.executeItem(itemAndId))
          }
        }

      case let .executeItem(itemAndId):
        return .run { send in
          await executeItem(itemAndId.item, itemAndId.id, send)
          send(.onItemTaskFinished(itemAndId.item, itemAndId.id))
        }

      case let .onItemProgress(item, id, progress):
        guard let sendItemProgress = sendItemProgress else {
          return .none
        }
        sendItemProgress(item, id, progress, &state)
        return .none

      case let .onItemTaskFinished(_, id):
        try? state.sendItemProgress(.finished(id))
        return .none

      case let .onItemTerminationConfirmed(id):
        state.executingItems.removeAll(where: { $0.id == id })
        return .value(.onNextItemsShouldBeExecuted)

      case .startQueue:
        state.isStarted = true
        let itemProgresses = state.sendItemProgress.itemProgressBroadcast
        return .run { send in
          send(.onNextItemsShouldBeExecuted)
          for try await progress in itemProgresses {
            switch progress {
            case let .finished(id):
              send(.onItemTerminationConfirmed(id))
            case .progress:
              break
            }
          }
        }

      case .stopQueue:
        return .none
      }
    }
  }
}

public extension Queue {
  struct ItemHandle: ItemHandleProtocol {
    public var cancel: () -> Void
    public var progressStream: AsyncStream<ItemProgress>
  }

  enum ItemProgressWrapper {
    case progress(ItemProgress)
    case finished(QueueItemId)

    public var id: QueueItemId {
      switch self {
      case let .progress(progress):
        return progress.itemId
      case let .finished(id):
        return id
      }
    }

    public var progress: ItemProgress? {
      switch self {
      case let .progress(progress):
        return progress
      case .finished:
        return nil
      }
    }

    public var isFinished: Bool {
      switch self {
      case .progress:
        return false
      case .finished:
        return true
      }
    }
  }

  struct SendItemProgress: Hashable {
    private let uuid = UUID()
    public var pipe: AsyncPipe<ItemProgressWrapper>
    public var itemProgressBroadcast: AsyncBroadcast<AsyncStream<ItemProgressWrapper>>

    public init() {
      pipe = AsyncPipe()
      itemProgressBroadcast = pipe.values.broadcast()
    }

    public func callAsFunction(_ progress: ItemProgressWrapper) throws {
      try pipe.send(progress)
    }

    public func progressForItemId(_ id: QueueItemId) -> AsyncStream<ItemProgress>? {
      try? itemProgressBroadcast
        .filter { $0.id == id }
        .prefix(while: { !$0.isFinished })
        .compactMap(\.progress)
        .eraseToAsyncStream()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(uuid)
    }
  }
}

public struct EmptyItemProgress<Item>: ItemProgressProtocol {
  public let itemId: QueueItemId
  public let item: Item
}
