import Foundation
import SwiftData

/// One item of a list kept in the app ("Weekend to-dos": "wash the car").
/// Items of one list share its name. All properties have defaults so the model can sync through CloudKit later.
@Model final class ListItem {
    var list = ""
    var text = ""
    var done = false
    var created = Date.now
    /// When the list was closed (taken off the panel). It is kept and can be reopened.
    var closed: Date?

    init(list: String, text: String) {
        self.list = list
        self.text = text
    }
}
