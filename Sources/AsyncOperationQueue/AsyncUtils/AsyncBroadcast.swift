import CloudKit
import Foundation

/// Broadcasts events to any subscribers.
///
/// A subscription is usually done via:
///
///     for await value in broadcast.values() { ... }
///
/// Once the instance of `AsyncBroadcast` is deallocated, the
/// `for await` loops are stopped.
public extension AsyncSequence {
  func broadcast() -> AsyncBroadcast<Self> {
    AsyncBroadcast(self)
  }
}

public class AsyncBroadcast<Upstream: AsyncSequence>: AsyncSequence {
  public typealias Element = Upstream.Element

  private var lastTag = 0
  private var pipes: [AsyncPipe<Element>] = []

  init(_ upstream: Upstream) {
    Task {
      for try await next in upstream {
        guard !Task.isCancelled else { break }
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        for pipeIndex in pipes.indices {
          let pipe = pipes[pipeIndex]
          do {
            try pipe.send(next)
          } catch {
            pipes.remove(at: pipeIndex)
          }
        }
      }
      os_unfair_lock_lock(lock)
      defer { os_unfair_lock_unlock(lock) }
      for pipe in pipes {
        pipe.finish()
      }
      pipes = []
    }
  }

  deinit {
    for pipe in pipes {
      pipe.finish()
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

  public final class Iterator: AsyncIteratorProtocol {
    var active: Bool = true
    private let pipe: AsyncPipe<Element>
    private var innerIterator: AsyncStream<Element>.Iterator

    init(pipe: AsyncPipe<Element>) {
      self.pipe = pipe
      innerIterator = pipe.values.makeAsyncIterator()
    }

    deinit {
      pipe.finish()
    }

    public func next() async throws -> Element? {
      guard active else { return nil }
      let next = await innerIterator.next()
      guard let next = next else {
        active = false
        pipe.finish()
        return nil
      }
      return next
    }
  }

  public func makeAsyncIterator() -> Iterator {
    let pipe = AsyncPipe<Element>()
    os_unfair_lock_lock(lock)
    pipes.append(pipe)
    os_unfair_lock_unlock(lock)
    pipe.onFinished = { [weak self] in
      guard let self = self else { return }
      os_unfair_lock_lock(self.lock)
      self.pipes.removeAll(where: { $0 === pipe })
      os_unfair_lock_unlock(self.lock)
    }
    return Iterator(pipe: pipe)
  }
}
