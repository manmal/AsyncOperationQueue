import Foundation

public struct Reducer<State, Action, Environment> {
  private let reducer: (inout State, Action, Environment) -> Effect<Action, Never>

  public init(_ reducer: @escaping (inout State, Action, Environment) -> Effect<Action, Never>) {
    self.reducer = reducer
  }

  public static var empty: Reducer {
    Self { _, _, _ in .none }
  }

  public func run(
    _ state: inout State,
    _ action: Action,
    _ environment: Environment
  ) -> Effect<Action, Never> {
    reducer(&state, action, environment)
  }
}
