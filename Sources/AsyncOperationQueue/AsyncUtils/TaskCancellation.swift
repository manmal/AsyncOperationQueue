import Foundation

public extension Task {
  /// Cancels this `Task` when the surrounding `Task` is cancelled.
  /// This is necessary if `Task {}` and `Task.detached {}`
  /// should be automatically cancelled - otherwise, such Tasks
  /// just run until finished.
  ///
  /// Usage:
  ///
  ///     await Task { await myAsyncFunc() }.autoCancel()
  @discardableResult
  func cancellable() async -> Self {
    await withTaskCancellationHandler(
      handler: { self.cancel() },
      operation: { () }
    )
    return self
  }

  func cancellableWaitUntilFinished() async {
    _ = await cancellableResult
  }

  /// Returns this `Task`'s result and cancels this `Task` when
  /// the surrounding `Task` is cancelled. This is necessary if
  /// `Task {}` and `Task.detached {}` should be automatically
  /// cancelled - otherwise, such Tasks just run until finished.
  ///
  /// Usage:
  ///
  ///     let result = await Task { await myAsyncFunc() }
  ///         .resultWithAutoCancel
  var cancellableResult: Result<Success, Failure> {
    get async {
      await withTaskCancellationHandler(
        handler: { self.cancel() },
        operation: { await self.result }
      )
    }
  }

  var cancellableValue: Success {
    get async throws {
      try await cancellableResult.get()
    }
  }
}
