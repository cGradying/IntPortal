import Foundation

struct Credentials: Codable, Equatable {
    var studentNumber: String
    var birthMonth: Int
    var birthDay: Int
    var birthYear: Int
    var password: String
}
