import Foundation

/// Provides a safe stream of values that are pushed in
/// on one side (via `send`), and come out at the other
/// side (`values`).
public final class AsyncPipe<T> {
  /// ⚠️ Only ever use `values` once per `AsyncQueue` instance.
  /// Adding multiple subscribers to `values` would not
  /// distribute the values to both subscribers, but only
  /// one of them.
  public let values: AsyncStream<T>
  private let input: AsyncStream<T>.Continuation
  private var isFinished: Bool = false {
    didSet {
      if isFinished {
        onFinished?()
      }
    }
  }

  public var onFinished: (() -> Void)?

  // Creating an unfair_lock properly is tricky. This code has been
  // acknowledged in the Swift forums:
  // https://forums.swift.org/t/how-do-you-use-asyncstream-to-make-task-execution-deterministic/57968/13
  private let lock: UnsafeMutablePointer<os_unfair_lock> = {
    let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    pointer.initialize(to: os_unfair_lock())
    return pointer
  }()

  public init(
    bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .unbounded
  ) {
    var input: AsyncStream<T>.Continuation!
    values = AsyncStream<T>(bufferingPolicy: bufferingPolicy) { input = $0 }
    self.input = input
    input.onTermination = { @Sendable [weak self] _ in
      guard let self = self else { return }
      os_unfair_lock_lock(self.lock)
      defer { os_unfair_lock_unlock(self.lock) }
      self.isFinished = true
    }
  }

  deinit {
    finish()
  }

  public func send(_ value: T) throws {
    os_unfair_lock_lock(lock)
    defer { os_unfair_lock_unlock(lock) }
    guard !isFinished else { throw CancellationError() }
    input.yield(value)
  }

  public func finish() {
    os_unfair_lock_lock(lock)
    guard !isFinished else { return }
    isFinished = true
    os_unfair_lock_unlock(lock)
    input.finish()
    input.onTermination = nil
  }

  /// Use with caution!
  public func getInput() -> AsyncStream<T>.Continuation {
    input
  }
}
