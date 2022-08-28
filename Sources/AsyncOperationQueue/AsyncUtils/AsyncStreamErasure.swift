import Foundation

public extension AsyncSequence {
  func eraseToAsyncStream() -> AsyncStream<Element> {
    AsyncStream { continuation in
      let task = Task {
        do {
          for try await element in self {
            guard !Task.isCancelled else { break }
            continuation.yield(element)
          }
          continuation.finish()
        } catch {
          continuation.finish()
        }
      }
      continuation.onTermination = { @Sendable _ in task.cancel() }
    }
  }
}
