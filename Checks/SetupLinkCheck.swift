// Self-check for SetupLink: the QR payload survives the round trip, anything else is refused. Run from the repo root:
// swiftc -parse-as-library -o /tmp/setuplinkcheck Sara/Models/SetupLink.swift Sara/Services/Keychain.swift Sara/Services/CloudSettings.swift Checks/SetupLinkCheck.swift && /tmp/setuplinkcheck
import Foundation

@main
enum SetupLinkCheck {
    static func main() {
        let link = SetupLink(values: ["anthropicKey": "sk-ant-???>>>~~~", "haToken": "eyJ.a/b+c", "yandexToken": "", "haURL": "http://192.168.1.10:8123",
                                      "model": "claude-opus-5-5", "houseNotes": "Line \"one\"\nline two ???"])
        let payload = link.payload!
        assert(payload.hasPrefix("SARA1:"))
        assert(SetupLink(payload: payload) == link)
        assert(link.homeHost == "192.168.1.10")

        assert(SetupLink(payload: String(payload.dropFirst(6))) == nil)
        assert(SetupLink(payload: "SARA1:garbage") == nil)
        assert(SetupLink(payload: "https://example.com") == nil)
        print("SetupLink: ok")
    }
}
