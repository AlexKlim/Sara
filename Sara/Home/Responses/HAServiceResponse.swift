import Foundation

struct HAServiceResponse<Response: Decodable>: Decodable {
    var response: Response

    private enum CodingKeys: String, CodingKey {
        case response = "service_response"
    }
}
