// Self-check for LiveContext: names come only from entries of the asked domains. Run from the repo root:
// swiftc -parse-as-library -o /tmp/livecontextcheck Sara/Home/LiveContext.swift Checks/LiveContextCheck.swift && /tmp/livecontextcheck
import Foundation

@main
enum LiveContextCheck {
    static func main() {
        let yaml = """
        Live Context: An overview of the areas and the devices in this smart home:
        - names: Fridge temperature, Fridge
          domain: number
          state: '6'
        - names: Display Limit
          domain: sensor
          state: '3'
        - names: 'Pool: target'
          domain: input_number
          state: '28'
        """
        let wrapped = String(data: try! JSONSerialization.data(withJSONObject: ["success": true, "result": yaml]), encoding: .utf8)!
        for text in [yaml, wrapped] {
            let names = LiveContext.names(in: text, domains: ["number", "input_number"])
            assert(names == ["Fridge temperature", "Fridge", "Pool: target"], "\(names)")
        }
        assert(LiveContext.names(in: yaml, domains: ["number"]).contains("Display Limit") == false)
        assert(LiveContext.names(in: "", domains: ["number"]).isEmpty)
        print("LiveContext: ok")
    }
}
