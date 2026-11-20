// Self-check for LiveContext: a name counts only as a whole name of an entry in the asked domains. Run from the repo root:
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
        - names: Pool "Heater"
          domain: number
          state: '1'
        - names: Fridge, target
          domain: number
          state: '2'
        """
        let wrapped = String(data: try! JSONSerialization.data(withJSONObject: ["success": true, "result": yaml]), encoding: .utf8)!
        let numbers: Set = ["number", "input_number"]
        for text in [yaml, wrapped] {
            for name in ["Fridge temperature", "Fridge", "Pool: target", "Pool \"Heater\"", "Fridge, target"] {
                assert(LiveContext.exposes(name, in: text, domains: numbers), name)
            }
            for name in ["Limit", "Display Limit", "temperature", "Fridge temp", "Pool"] {
                assert(!LiveContext.exposes(name, in: text, domains: numbers), name)
            }
        }
        assert(!LiveContext.exposes("Fridge", in: "", domains: numbers))
        print("LiveContext: ok")
    }
}
