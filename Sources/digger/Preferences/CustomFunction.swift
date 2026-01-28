import Foundation

struct CustomFunction: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var prompt: String

    init(id: UUID = UUID(), title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }
}
