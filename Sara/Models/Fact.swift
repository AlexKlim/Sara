import Foundation
import SwiftData

/// One long-term memory fact, e.g. "evening_light" = "Likes warm 2700K light in the evening".
/// All properties have defaults, as CloudKit sync requires.
@Model final class Fact {
    /// Unique key in snake_case. Saving a fact with an existing name replaces it.
    var name = ""
    /// preference, routine, person, correction or other.
    var type = "other"
    var content = ""
    var updated = Date.now

    init(name: String, type: String, content: String) {
        self.name = name
        self.type = type
        self.content = content
    }
}
