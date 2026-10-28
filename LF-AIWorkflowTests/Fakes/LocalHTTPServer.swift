//
//  LocalHTTPServer.swift
//  LF-AIWorkflowTests
//

import Foundation
import Network
import os

/// Tiny HTTP/1.1 server on 127.0.0.1 (random port). Records request paths and times.
final class LocalHTTPServer: Sendable {
    struct Response: Sendable {
        var status = 200
        var contentType = "text/html; charset=utf-8"
        var body: String
    }

    struct Request: Sendable { let path: String; let time: ContinuousClock.Instant }

    private struct State { var routes: [String: Response]; var requests: [Request] = [] }

    private let listener: NWListener
    private let state: OSAllocatedUnfairLock<State>
    private let queue = DispatchQueue(label: "LocalHTTPServer")
    let port: UInt16

    var requests: [Request] { state.withLock { $0.requests } }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    static func start(routes: [String: Response]) async throws -> LocalHTTPServer {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        let state = OSAllocatedUnfairLock(initialState: State(routes: routes))
        let queue = DispatchQueue(label: "LocalHTTPServer")
        listener.newConnectionHandler = { conn in
            conn.start(queue: queue)
            Self.receive(conn, buffer: Data(), state: state)
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { s in
                switch s {
                case .ready:
                    if once.withLock({ let was = $0; $0 = true; return !was }), let p = listener.port?.rawValue {
                        cont.resume(returning: p)
                    }
                case .failed(let e):
                    if once.withLock({ let was = $0; $0 = true; return !was }) { cont.resume(throwing: e) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return LocalHTTPServer(listener: listener, state: state, port: port)
    }

    private init(listener: NWListener, state: OSAllocatedUnfairLock<State>, port: UInt16) {
        self.listener = listener
        self.state = state
        self.port = port
    }

    func stop() { listener.cancel() }

    private static func receive(_ conn: NWConnection, buffer: Data, state: OSAllocatedUnfairLock<State>) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, done, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                respond(conn, head: String(decoding: buf[..<range.lowerBound], as: UTF8.self), state: state)
            } else if done || error != nil {
                conn.cancel()
            } else {
                receive(conn, buffer: buf, state: state)
            }
        }
    }

    private static func respond(_ conn: NWConnection, head: String, state: OSAllocatedUnfairLock<State>) {
        let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
        let path = parts.count > 1 ? String(parts[1]) : "/"
        let response = state.withLock { s -> Response in
            s.requests.append(Request(path: path, time: .now))
            return s.routes[path] ?? Response(status: 404, contentType: "text/plain", body: "not found")
        }
        let body = Data(response.body.utf8)
        let header = "HTTP/1.1 \(response.status) X\r\nContent-Type: \(response.contentType)\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }
}
