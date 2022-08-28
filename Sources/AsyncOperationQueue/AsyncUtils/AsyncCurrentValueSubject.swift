import Foundation

/// Subject that holds the current value and broadcasts events to
/// any subscribers.
///
/// A subscription is
/// usually done via:
///
///     for await value in subject.values() { ... }
///
/// Once the instance of `AsyncCurrentValueSubject` is deallocated, the
/// `for await` loops are stopped.
public class AsyncCurrentValueSubject<T> {
  private var listeners: [(AsyncStream<T>.Continuation, Int)] = []
  private var lastListenerTag = 0
  private var _value: T

  public var value: T {
    get {
      let value: T
      os_unfair_lock_lock(lock)
      value = _value
      os_unfair_lock_unlock(lock)
      return value
    }
    set {
      send(newValue)
    }
  }

  // Creating an unfair_lock properly is tricky. This code has been
  // acknowledged in the Swift forums:
  // https://forums.swift.org/t/how-do-you-use-asyncstream-to-make-task-execution-deterministic/57968/13
  private let lock: UnsafeMutablePointer<os_unfair_lock> = {
    let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    pointer.initialize(to: os_unfair_lock())
    return pointer
  }()

  public init(_ value: T) {
    _value = value
  }

  public func values() -> AsyncStream<T> {
    AsyncStream(
      T.self,
      bufferingPolicy: .unbounded
    ) { continuation in
      os_unfair_lock_lock(lock)
      listeners.append((continuation, lastListenerTag))
      continuation.onTermination = { [weak self, lastListenerTag] _ in
        self?.removeEventListener(lastListenerTag)
      }
      lastListenerTag += 1
      os_unfair_lock_unlock(lock)
    }
  }

  public func send(_ value: T) {
    os_unfair_lock_lock(lock)
    _value = value
    for (listener, _) in listeners {
      listener.yield(value)
    }
    os_unfair_lock_unlock(lock)
  }

  public func reBroadcast(_ stream: AsyncStream<T>) -> Task<Void, Never> {
    Task(priority: .userInitiated) { [weak self] in
      for await value in stream {
        guard !Task.isCancelled, let self = self else { break }
        self.send(value)
      }
    }
  }

  deinit {
    os_unfair_lock_lock(lock)
    for (listener, _) in listeners {
      listener.finish()
    }
    os_unfair_lock_unlock(lock)
  }

  private func removeEventListener(_: Int) {
    os_unfair_lock_lock(lock)
    listeners.removeAll(where: { $0.1 == lastListenerTag })
    os_unfair_lock_unlock(lock)
  }
}
