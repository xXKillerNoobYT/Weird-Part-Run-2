import Foundation
import Network

struct HTTPStubRequest: Sendable {
    let path: String
}

struct HTTPStubResponse: Sendable {
    let statusCode: Int
    let body: String
}

final class HTTPStubServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: @Sendable (HTTPStubRequest) -> HTTPStubResponse
    private let queue = DispatchQueue(label: "com.wiredpart.tests.httpstub")

    init(statusCode: Int, body: String) throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        self.handler = { _ in HTTPStubResponse(statusCode: statusCode, body: body) }
    }

    init(handler: @escaping @Sendable (HTTPStubRequest) -> HTTPStubResponse) throws {
        self.listener = try NWListener(using: .tcp, on: .any)
        self.handler = handler
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = HTTPStubOneShotContinuationBox(continuation)

            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        continuationBox.resume(.success(port.rawValue))
                    } else {
                        continuationBox.resume(.failure(URLError(.badServerResponse)))
                    }
                case .failed(let error):
                    continuationBox.resume(.failure(error))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [handler, queue] connection in
                connection.start(queue: queue)

                @Sendable func sendResponse(for requestData: Data) {
                    let rawRequest = String(data: requestData, encoding: .utf8) ?? ""
                    let requestLine = rawRequest.components(separatedBy: "\r\n").first ?? ""
                    let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    let stubResponse = handler(HTTPStubRequest(path: path))
                    let statusText = (200..<300).contains(stubResponse.statusCode) ? "OK" : "Error"
                    let response = """
                    HTTP/1.1 \(stubResponse.statusCode) \(statusText)\r
                    Content-Type: application/json\r
                    Content-Length: \(stubResponse.body.utf8.count)\r
                    Connection: close\r
                    \r
                    \(stubResponse.body)
                    """
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }

                @Sendable func receive(_ buffered: Data) {
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                        if error != nil {
                            connection.cancel()
                            return
                        }

                        var requestData = buffered
                        if let data {
                            requestData.append(data)
                        }

                        guard requestData.containsHTTPHeaderTerminator || isComplete else {
                            receive(requestData)
                            return
                        }

                        sendResponse(for: requestData)
                    }
                }

                receive(Data())
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }
}

private final class HTTPStubOneShotContinuationBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<UInt16, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private extension Data {
    var containsHTTPHeaderTerminator: Bool {
        guard count >= 4 else { return false }
        return zip(zip(zip(self, dropFirst()), dropFirst(2)), dropFirst(3)).contains { firstThree, fourth in
            let ((first, second), third) = firstThree
            return first == 13 && second == 10 && third == 13 && fourth == 10
        }
    }
}
