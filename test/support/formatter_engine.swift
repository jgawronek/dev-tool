import Foundation
import JavaScriptCore

// Exercise the same bundled assets and JavaScriptCore API as the macOS channel.
let context = JSContext()!
for name in ["typescript-5.9.3.js", "formatter-vendors.js", "tool-code-engine.js"] {
    context.evaluateScript(try String(contentsOfFile: "assets/javascript/\(name)", encoding: .utf8))
    if let exception = context.exception {
        fatalError(exception.toString())
    }
}
while let line = readLine() {
    let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: String]
    let result = context.objectForKeyedSubscript("devutilsCodeOperation")!.call(withArguments: [
        request["source"] ?? "", request["operation"] ?? "Beautify", request["indentation"] ?? "2 spaces"
    ])!
    if let exception = context.exception { fatalError(exception.toString()) }
    let data = try JSONSerialization.data(withJSONObject: result.toDictionary()!)
    print(String(data: data, encoding: .utf8)!)
}
