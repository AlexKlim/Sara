// Self-check for SetupLink: the QR link survives the round trip, anything else is refused. Run from the repo root:
// swiftc -parse-as-library -o /tmp/setuplinkcheck Sara/Models/SetupLink.swift Sara/Services/Keychain.swift Sara/Services/CloudSettings.swift Checks/SetupLinkCheck.swift && /tmp/setuplinkcheck
import Foundation

@main
enum SetupLinkCheck {
    static func main() {
        // Characters that turn into "+" and "/" in plain base64, and notes with quotes and new lines.
        let link = SetupLink(values: ["anthropicKey": "sk-ant-???>>>~~~", "haToken": "eyJ.a/b+c", "yandexToken": "", "haURL": "http://192.168.1.10:8123",
                                      "model": "claude-opus-5-5", "houseNotes": "Line \"one\"\nline two ???"])
        let url = link.url!
        assert(url.absoluteString.hasPrefix("sara-home://connect?d="))
        assert(!url.query!.dropFirst(2).contains("+") && !url.query!.dropFirst(2).contains("="))
        assert(SetupLink(url: url) == link)
        assert(link.homeHost == "192.168.1.10")

        assert(SetupLink(url: URL(string: "https://connect?d=" + url.query!.dropFirst(2))!) == nil)
        assert(SetupLink(url: URL(string: "sara-home://other?d=" + url.query!.dropFirst(2))!) == nil)
        assert(SetupLink(url: URL(string: "sara-home://connect?d=garbage")!) == nil)
        assert(SetupLink(url: URL(string: "sara-home://connect")!) == nil)
        print("SetupLink: ok")
    }
}
