import Foundation
import MotoMirrorCore

enum MCP {
    static func run(toolbox: AgentToolbox) async throws -> Int32 {
        writeStandardError("MotoMirror MCP server ready on stdio")
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                writeMCP(["jsonrpc": "2.0", "id": NSNull(), "error": [
                    "code": -32700, "message": "Parse error"
                ]])
                continue
            }
            await handle(request, toolbox: toolbox)
        }
        return 0
    }

    private static func handle(_ request: [String: Any], toolbox: AgentToolbox) async {
        let id = request["id"] ?? NSNull()
        guard let method = request["method"] as? String else {
            writeMCP(["jsonrpc": "2.0", "id": id, "error": [
                "code": -32600, "message": "Invalid Request"
            ]])
            return
        }
        if method.hasPrefix("notifications/") { return }

        switch method {
        case "initialize":
            writeMCP([
                "jsonrpc": "2.0", "id": id,
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "motomirror", "version": "1.0.0"]
                ]
            ])
        case "ping":
            writeMCP(["jsonrpc": "2.0", "id": id, "result": [:]])
        case "tools/list":
            let tools = await toolbox.tools().map { spec -> [String: Any] in
                [
                    "name": spec.name,
                    "description": spec.description,
                    "inputSchema": spec.inputSchema
                ]
            }
            writeMCP(["jsonrpc": "2.0", "id": id, "result": ["tools": tools]])
        case "tools/call":
            let params = request["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String else {
                writeMCP(["jsonrpc": "2.0", "id": id, "error": [
                    "code": -32602, "message": "Missing tool name"
                ]])
                return
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let result = try await toolbox.call(name, arguments: arguments)
                var content: [[String: Any]] = []
                if let image = result.imageBase64 {
                    content.append([
                        "type": "image",
                        "data": image,
                        "mimeType": "image/png"
                    ])
                }
                content.append(["type": "text", "text": result.text])
                writeMCP([
                    "jsonrpc": "2.0", "id": id,
                    "result": [
                        "content": content,
                        "isError": result.isError
                    ]
                ])
            } catch {
                writeMCP([
                    "jsonrpc": "2.0", "id": id,
                    "result": [
                        "content": [["type": "text", "text": error.localizedDescription]],
                        "isError": true
                    ]
                ])
            }
        default:
            writeMCP(["jsonrpc": "2.0", "id": id, "error": [
                "code": -32601, "message": "Method not found: \(method)"
            ]])
        }
    }

    private static func writeMCP(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            writeStandardError("Could not encode MCP response")
            return
        }
        FileHandle.standardOutput.write((string + "\n").data(using: .utf8)!)
    }
}
