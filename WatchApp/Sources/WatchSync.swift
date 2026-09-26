import FoGKit
import Foundation
import WatchConnectivity

/// Watch side of WatchConnectivity. Events use `transferUserInfo`, which is queued and delivered
/// even if the phone is out of range, so no freeze is lost from the caregiver's log.
final class WatchSync: NSObject, WCSessionDelegate {
    var onMessage: ((SyncMessage) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ message: SyncMessage) {
        guard WCSession.default.activationState == .activated, let data = try? message.encoded() else { return }
        WCSession.default.transferUserInfo([SyncMessage.key: data])
    }

    func sendFile(_ url: URL) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferFile(url, metadata: ["kind": "study_windows"])
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let data = session.receivedApplicationContext[SyncMessage.key] as? Data { deliver(data) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[SyncMessage.key] as? Data { deliver(data) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[SyncMessage.key] as? Data { deliver(data) }
    }

    private func deliver(_ data: Data) {
        guard let m = try? SyncMessage.decode(data) else { return }
        DispatchQueue.main.async { self.onMessage?(m) }
    }
}
