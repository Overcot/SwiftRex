import SwiftRex

class ActionReference: ActionProtocol, Equatable {
    static func == (lhs: ActionReference, rhs: ActionReference) -> Bool {
        lhs === rhs
    }
}
