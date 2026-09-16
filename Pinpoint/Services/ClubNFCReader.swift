import CoreNFC
import Foundation

@MainActor @Observable
final class ClubNFCReader: NSObject, @preconcurrency NFCTagReaderSessionDelegate {
    var scanning = false
    var message = "Hold the club’s tag near the top of your iPhone."
    @ObservationIgnored private var session: NFCTagReaderSession?
    @ObservationIgnored private var completion: ((String) -> Void)?
    static var available: Bool { NFCTagReaderSession.readingAvailable }

    func scan(prompt: String, completion: @escaping (String) -> Void) {
        guard session == nil else { return }
        guard Self.available else {
            message = "NFC requires a compatible iPhone. It is not available in the simulator."
            return
        }
        self.completion = completion
        let reader = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
        session = reader
        scanning = true
        reader?.alertMessage = prompt
        reader?.begin()
    }
    func cancel() {
        completion = nil
        session?.invalidate()
        session = nil
        scanning = false
    }
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard self.session === session else { return }
        self.session = nil; scanning = false; completion = nil
        if (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled {
            message = "Scan cancelled. No changes made."
        } else { message = "Scan ended. Try again. \(error.localizedDescription)" }
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard self.session === session else { return }
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "More than one tag detected. Hold only one club near your iPhone."
            session.restartPolling(); return
        }
        let key: String
        switch tag {
        case .miFare(let value): key = "mifare:" + value.identifier.map { String(format: "%02x", $0) }.joined()
        case .iso15693(let value): key = "iso15693:" + value.identifier.map { String(format: "%02x", $0) }.joined()
        default:
            session.invalidate(errorMessage: "Use an NTAG213/215/216 or ISO 15693 club tag.")
            return
        }
        guard !key.hasSuffix(":") else { session.invalidate(errorMessage: "This tag has no stable identifier."); return }
        let callback = completion
        completion = nil; self.session = nil; scanning = false
        message = "Tag read."
        session.alertMessage = "Club tag read."
        session.invalidate()
        callback?(key)
    }
}
