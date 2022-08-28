import XCTest
@testable import AsyncOperationQueue

final class ReduxTests: XCTestCase {
  func testSimpleStore() async throws {
    let store = Store<Simple.State, Simple.Action>(
      initialState: Simple.State(),
      reducer: .simple(),
      environment: Simple.Env()
    )
    let states = store.stream
    Task {
      for await state in states {
        print(state)
      }
    }
    if let task = await store.send(.one) {
      await task.cancellableWaitUntilFinished()
    }
    XCTAssertFalse(store.state.hasOne)
    XCTAssertFalse(store.state.hasTwo)
    XCTAssertFalse(store.state.hasThree)
    await Task.yield()
  }

  func testCounterStore() async throws {
    let store = Store<Counter.State, Counter.Action>(
      initialState: Counter.State(),
      reducer: .counter(),
      environment: Counter.Env()
    )
    await withTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 1000 {
        group.addTask {
          await(store.send(.add))?.cancellableWaitUntilFinished()
        }
      }
      for _ in 0 ..< 999 {
        group.addTask {
          await(store.send(.subtract))?.cancellableWaitUntilFinished()
        }
      }
      await group.waitForAll()
    }
    XCTAssertEqual(store.state.count, 1)
  }
}

enum Simple {
  enum Action {
    case one
    case two
    case three
    case reset
  }

  struct State {
    var hasOne: Bool = false
    var hasTwo: Bool = false
    var hasThree: Bool = false
  }

  struct Env {}
}

enum Counter {
  enum Action {
    case add
    case subtract
    case doAdd
    case doSubtract
  }

  struct State {
    var count = 0
  }

  struct Env {}
}

extension Reducer
  where State == Simple.State, Action == Simple.Action, Environment == Simple.Env {
  static func simple() -> Self {
    Reducer { state, action, _ in
      switch action {
      case .one:
        state.hasOne = true
        return Effect.value(.two)
      case .two:
        state.hasTwo = true
        return Effect.run { send in
          send(.three)
        }
      case .three:
        state.hasThree = true
        return Effect.run(
          operation: { _ in
            throw NSError(domain: "MyDomain", code: 42)
          },
          catch: { _, send in
            send(.reset)
          }
        )
      case .reset:
        state = Simple.State()
        return .none
      }
    }
  }
}

extension Reducer
  where State == Counter.State, Action == Counter.Action, Environment == Counter.Env {
  static func counter() -> Self {
    Reducer { state, action, _ in
      switch action {
      case .add:
        return Effect.run { send in
          send(.doAdd)
        }
      case .subtract:
        return Effect.run { send in
          send(.doSubtract)
        }
      case .doAdd:
        state.count += 1
        return Effect.none
      case .doSubtract:
        state.count -= 1
        return Effect.none
      }
    }
  }
}
