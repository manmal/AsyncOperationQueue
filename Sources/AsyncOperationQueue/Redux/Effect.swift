import Foundation
import SwiftUI

// Heavily (!) inspired by TCA's Effect:
// https://github.com/pointfreeco/swift-composable-architecture/blob/main/Sources/ComposableArchitecture/Effect.swift
public enum Effect<Output, Failure: Error> {
  public typealias MakeTask = () -> (Task<Void, Never>, AsyncStream<Result<Output, Failure>>)

  case none
  case result(Result<Output, Failure>)
  case task(MakeTask)
}

public extension Effect where Failure == Never {
  static func value(_ value: Output) -> Self {
    .result(.success(value))
  }

  static func run(
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable (Send<Output>) async throws -> Void,
    catch handler: (@Sendable (Error, Send<Output>) async -> Void)? = nil
  ) -> Self {
    .task {
      let pipe = AsyncPipe<Result<Output, Failure>>()
      let task = Task(priority: priority) {
        defer { pipe.finish() }
        let send = Send<Output>(
          send: {
            do {
              try pipe.send(.success($0))
            } catch {
              assertionFailure("Can't send action because processing has stopped!")
            }
          }
        )

        do {
          try await operation(send)
        } catch is CancellationError {
          return
        } catch {
          guard let handler = handler else {
            return
          }
          await handler(error, send)
        }
      }
      return (task, pipe.values)
    }
  }
}

public struct Send<Action> {
  public let send: (Action) -> Void

  public init(send: @escaping (Action) -> Void) {
    self.send = send
  }

  /// Sends an action back into the system from an effect.
  ///
  /// - Parameter action: An action.
  public func callAsFunction(_ action: Action) {
    guard !Task.isCancelled else { return }
    send(action)
  }

  /// Sends an action back into the system from an effect with animation.
  ///
  /// - Parameters:
  ///   - action: An action.
  ///   - animation: An animation.
  public func callAsFunction(_ action: Action, animation: Animation?) {
    guard !Task.isCancelled else { return }
    withAnimation(animation) {
      self(action)
    }
  }
}
