//    MIT License
//
//    Copyright (c) 2020 Point-Free, Inc.
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import CustomDump
import Foundation

/// Determines how the string description of an action should be printed when using the
/// ``Reducer/debug(_:state:action:actionFormat:environment:)`` higher-order reducer.
public enum ActionFormat {
  /// Prints the action in a single line by only specifying the labels of the associated values:
  ///
  /// ```swift
  /// Action.screenA(.row(index:, action: .textChanged(query:)))
  /// ```
  ///
  case labelsOnly
  /// Prints the action in a multiline, pretty-printed format, including all the labels of
  /// any associated values, as well as the data held in the associated values:
  ///
  /// ```swift
  /// Action.screenA(
  ///   ScreenA.row(
  ///     index: 1,
  ///     action: RowAction.textChanged(
  ///       query: "Hi"
  ///     )
  ///   )
  /// )
  /// ```
  ///
  case prettyPrint
}

public extension Reducer {
  /// Prints debug messages describing all received actions and state mutations.
  ///
  /// Printing is only done in debug (`#if DEBUG`) builds.
  ///
  /// - Parameters:
  ///   - prefix: A string with which to prefix all debug messages.
  ///   - toDebugEnvironment: A function that transforms an environment into a debug environment by
  ///     describing a print function and a queue to print from. Defaults to a function that ignores
  ///     the environment and returns a default ``DebugEnvironment`` that uses Swift's `print`
  ///     function and a background queue.
  /// - Returns: A reducer that prints debug messages for all received actions.
  func debug(
    _ prefix: String = "",
    actionFormat: ActionFormat = .prettyPrint,
    environment toDebugEnvironment: @escaping (Environment) -> DebugEnvironment = { _ in
      DebugEnvironment()
    }
  ) -> Self {
    #if DEBUG
      return .init { state, action, environment in
        let previousState = state
        let effects = self.run(&state, action, environment)
        let nextState = state
        let debugEnvironment = toDebugEnvironment(environment)
        return .run { send in
          debugEnvironment.queue.async {
            var actionOutput = ""
            if actionFormat == .prettyPrint {
              customDump(action, to: &actionOutput, indent: 2)
            } else {
              actionOutput.write(debugCaseOutput(action).indent(by: 2))
            }
            let stateOutput =
              State.self == Void.self
                ? ""
                : diff(previousState, nextState)
                .map { "\($0)\n" } ?? "  (No state changes)\n"
            debugEnvironment.printer(
              """
              \(prefix.isEmpty ? "" : "\(prefix): ")received action:
              \(actionOutput)
              \(stateOutput)
              """
            )
          }

          switch effects {
          case .none:
            break
          case let .result(result):
            send(try! result.get())
          case let .task(makeTask):
            let (task, stream) = makeTask()
            await Task {
              for await nextAction in stream {
                send(try! nextAction.get())
              }
              await task.cancellableWaitUntilFinished()
            }.cancellableWaitUntilFinished()
          }
        }
      }
    #else
      return self
    #endif
  }
}

/// An environment for debug-printing reducers.
public struct DebugEnvironment {
  public var printer: (String) -> Void
  public var queue: DispatchQueue

  public init(
    printer: @escaping (String) -> Void = { print($0) },
    queue: DispatchQueue
  ) {
    self.printer = printer
    self.queue = queue
  }

  public init(
    printer: @escaping (String) -> Void = { print($0) }
  ) {
    self.init(printer: printer, queue: _queue)
  }
}

private let _queue = DispatchQueue(
  label: "co.pointfree.ComposableArchitecture.DebugEnvironment",
  qos: .default
)

func debugCaseOutput(_ value: Any) -> String {
  func debugCaseOutputHelp(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .enum:
      guard let child = mirror.children.first else {
        let childOutput = "\(value)"
        return childOutput == "\(type(of: value))" ? "" : ".\(childOutput)"
      }
      let childOutput = debugCaseOutputHelp(child.value)
      return ".\(child.label ?? "")\(childOutput.isEmpty ? "" : "(\(childOutput))")"
    case .tuple:
      return mirror.children.map { label, value in
        let childOutput = debugCaseOutputHelp(value)
        return
          "\(label.map { isUnlabeledArgument($0) ? "_:" : "\($0):" } ?? "")\(childOutput.isEmpty ? "" : " \(childOutput)")"
      }
      .joined(separator: ", ")
    default:
      return ""
    }
  }

  return (value as? CustomDebugStringConvertible)?.debugDescription
    ?? "\(type(of: value))\(debugCaseOutputHelp(value))"
}

private func isUnlabeledArgument(_ label: String) -> Bool {
  label.firstIndex(where: { $0 != "." && !$0.isNumber }) == nil
}

extension String {
  func indent(by indent: Int) -> String {
    let indentation = String(repeating: " ", count: indent)
    return indentation + replacingOccurrences(of: "\n", with: "\n\(indentation)")
  }
}
