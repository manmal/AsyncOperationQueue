import Foundation

public extension Queue {
  static func production<State, Action: ActionProtocol, Environment>(
    reducer: Reducer<State, Action, Environment>,
    initialState: State,
    environment: Environment,
    makeItemHandle: @escaping (Item, QueueItemId, State, AsyncStream<State>) -> ItemHandle?
  ) -> Self where Action.Item == Item, ItemHandle: ItemHandleProtocol {
    let store = Store<State, Action>(
      initialState: initialState,
      reducer: reducer,
      environment: environment
    )

    let sendAndForgetPipe = AsyncPipe<(Item, QueueItemId)>()

    Task {
      for await(item, id) in sendAndForgetPipe.values {
        store.sendAndForget(Action.addItemAction(item, id))
      }
    }

    return Queue(
      _start: {
        Task {
          await store.send(Action.startAction())
          await withTaskCancellationHandler(
            handler: { Task { await store.send(Action.stopAction()) } },
            operation: {
              // Sleep "forever" (~31 years) to keep Task alive so it can
              // be cancelled at some point
              try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 1_000_000_000)
            }
          )
        }
      },
      _add: { item, id in
        let handle = makeItemHandle(item, id, store.state, store.stream)
        try! sendAndForgetPipe.send((item, id))
        return handle
      }
    )
  }
}
