import Foundation

// Heavily (!) inspired by TCA's Store:
// https://github.com/pointfreeco/swift-composable-architecture/blob/main/Sources/ComposableArchitecture/Store.swift
public actor Store<State, Action> {
  public nonisolated var state: State { _state.value }
  public nonisolated var stream: AsyncStream<State> { _state.values() }

  private nonisolated let _state: AsyncCurrentValueSubject<State>
  private let reducer: (inout State, Action) -> Effect<Action, Never>
  private var bufferedActions: [Action] = []
  private var isSending = false
  private var effectCancellables: [UUID: AsyncCancellable] = [:]
  private nonisolated let sendAndForgetPipe: AsyncPipe<Action>
  private var isObservingSendAndForget = false

  init<Environment>(
    initialState: State,
    reducer: Reducer<State, Action, Environment>,
    environment: Environment
  ) {
    _state = AsyncCurrentValueSubject(initialState)
    self.reducer = { state, action in reducer.run(&state, action, environment) }
    sendAndForgetPipe = AsyncPipe()
  }

  @discardableResult
  func send(
    _ action: Action,
    originatingFrom _: Action? = nil
  ) -> Task<Void, Never>? {
    bufferedActions.append(action)
    guard !isSending else { return nil }

    isSending = true
    var currentState = _state.value
    defer {
      self.isSending = false
      _state.value = currentState
    }

    let tasks = Box<[Task<Void, Never>]>(wrappedValue: [])

    while !bufferedActions.isEmpty {
      let action = bufferedActions.removeFirst()
      let effect = reducer(&currentState, action)

      switch effect {
      case .none:
        break

      case let .result(result):
        if let task = send(try! result.get(), originatingFrom: action) {
          tasks.wrappedValue.append(task)
        }

      case let .task(makeTaskAndStream):
        let uuid = UUID()
        let task = Task {
          let (operationTask, stream) = makeTaskAndStream()
          let processNextActionsTask = Task {
            for await nextAction in stream {
              guard !Task.isCancelled else {
                break
              }
              if let task = self
                .send(try! nextAction.get(), originatingFrom: action) {
                tasks.wrappedValue.append(task)
              }
            }
            // Cleanup is always executed once the Task has been started:
            self.effectCancellables[uuid] = nil
          }
          await processNextActionsTask.cancellable()
          await operationTask.cancellableWaitUntilFinished()
        }
        tasks.wrappedValue.append(task)
        effectCancellables[uuid] = { task.cancel() }
      }
    }

    return Task {
      await withTaskCancellationHandler {
        var index = tasks.wrappedValue.startIndex
        while index < tasks.wrappedValue.endIndex {
          defer { index += 1 }
          tasks.wrappedValue[index].cancel()
        }
      } operation: {
        var index = tasks.wrappedValue.startIndex
        while index < tasks.wrappedValue.endIndex {
          defer { index += 1 }
          await tasks.wrappedValue[index].value
        }
      }
    }
  }

  nonisolated func sendAndForget(_ action: Action) {
    do {
      try sendAndForgetPipe.send(action)
      Task { await startObservingSendAndForget() }
    } catch {
      assertionFailure("sendAndForgetPipe threw")
    }
  }

  private func startObservingSendAndForget() {
    guard !isObservingSendAndForget else { return }
    isObservingSendAndForget = true
    Task {
      for await action in sendAndForgetPipe.values {
        await Task.yield()
        send(action)
      }
    }
  }
}

public typealias AsyncCancellable = () -> Void
