import XCTest
@testable import AsyncOperationQueue

final class AsyncOperationQueueTests: XCTestCase {
  func testCancellableSkippable() async throws {
    typealias QueueType = Queue<Int, EmptyItemProgress<Int>>
    let queue = Queue.production(
      reducer: Queue.reducer(
        executeItem: executeCancellableSkippableItem,
        sendItemProgress: { item, id, _, state in
          do {
            try state.sendItemProgress(.progress(.init(itemId: id, item: item)))
          } catch {
            assertionFailure("Can't send item progress because queue shut down")
          }
        }
      ),
      initialState: Queue.State(concurrentExecutions: 1),
      environment: (),
      makeItemHandle: {
        _, id, currentState, _ -> QueueType.ItemHandle? in
        guard let progress = currentState.sendItemProgress.progressForItemId(id) else {
          return nil
        }
        return Queue.ItemHandle(cancel: {}, progressStream: progress)
      }
    )

    _ = queue.start()

    let handlesAndItems = (0 ..< 1_000)
      .reduce(into: [(QueueType.ItemHandle, Int)]()) { partialResult, item in
        guard let handle = queue.add(item: item, id: QueueItemId()) else {
          XCTFail("Item not accepted by queue")
          fatalError()
        }
        partialResult.append((handle, item))
      }

    await withTaskGroup(of: Void.self) { taskGroup in
      for (handle, _) in handlesAndItems {
        taskGroup.addTask(priority: .userInitiated) {
          for await _ in handle.progressStream {}
        }
        await taskGroup.waitForAll()
      }
    }
  }
}

private func executeCancellableSkippableItem(
  item _: Int,
  id _: QueueItemId,
  send _: Send<Queue<Int, EmptyItemProgress<Int>>.Action>
) async {
//    send(.onItemProgress(item, id, .init(itemId: id, item: item)))
//    try? await Task.sleep(nanoseconds: 1)
}
