import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A response body was bigger than the caller allows. The transfer was
/// cancelled as soon as that was known, so the body was never held whole.
struct BodyTooLarge: Error {
    var limit: Int
}

/// Collects data tasks' bodies itself so a transfer can be cancelled once it
/// passes a size cap. `URLSession.data(for:)` holds the entire body before it
/// returns, which is too late to refuse one.
///
/// Create the session with this object as its delegate and call `fetch`.
class BoundedBodyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Transfer {
        var response: URLResponse?
        var data = Data()
        var limit: Int
        var exceeded = false
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    }

    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    /// Runs `request` on `session` and returns its body, or throws
    /// `BodyTooLarge` after cancelling the moment the body (or its declared
    /// length) exceeds `limit`.
    func fetch(_ request: URLRequest, on session: URLSession, limit: Int) async throws -> (Data, URLResponse) {
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                transfers[task.taskIdentifier] = Transfer(limit: limit, continuation: continuation)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let allowed: Bool
        if var transfer = transfers[dataTask.taskIdentifier] {
            transfer.response = response
            if response.expectedContentLength > Int64(transfer.limit) { transfer.exceeded = true }
            allowed = !transfer.exceeded
            transfers[dataTask.taskIdentifier] = transfer
        } else {
            allowed = false
        }
        lock.unlock()
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        var stop = false
        if var transfer = transfers[dataTask.taskIdentifier], !transfer.exceeded {
            transfer.data.append(data)
            if transfer.data.count > transfer.limit {
                transfer.exceeded = true
                transfer.data = Data()
                stop = true
            }
            transfers[dataTask.taskIdentifier] = transfer
        }
        lock.unlock()
        if stop { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let transfer = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let transfer, let continuation = transfer.continuation else { return }
        if transfer.exceeded {
            continuation.resume(throwing: BodyTooLarge(limit: transfer.limit))
        } else if let error {
            continuation.resume(throwing: error)
        } else if let response = transfer.response ?? task.response {
            continuation.resume(returning: (transfer.data, response))
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }
}
