import CoreImage
import PDFKit
import UIKit
import UserNotifications
import Vision

enum OCR {
    static func lines(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { done in
            let request = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let sorted = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                done.resume(returning: sorted.compactMap { $0.topCandidates(1).first?.string })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP"]
            let handler = VNImageRequestHandler(cgImage: cg, orientation: image.cgOrientation)
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { done.resume(returning: []) }
            }
        }
    }
}

extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

enum PDFThumb {
    static func image(_ url: URL) -> UIImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let box = page.bounds(for: .mediaBox)
        let scale = min(2, 1600 / max(box.width, box.height))
        return page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
    }
}

enum Reminders {
    static func sync(_ state: AppState, today: Day) async -> Bool {
        let center = UNUserNotificationCenter.current()
        if Launch.testFlag("-notifications-denied") { return true }
        center.removeAllPendingNotificationRequests()
        guard state.settings.reminders, !state.items.isEmpty, !Launch.testing else { return false }
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return true }
        for r in ReminderPlan.plan(state, today: today) {
            guard let item = state.items.first(where: { $0.id == r.itemID }),
                  let date = r.day.local(hour: state.settings.hour) else { continue }
            let content = UNMutableNotificationContent()
            content.title = ReminderPlan.title(r, name: item.displayName)
            content.body = ReminderPlan.body(r)
            content.sound = .default
            content.userInfo = ["item": item.id.uuidString]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
        return false
    }
}

enum QR {
    static func image(_ text: String, size: CGFloat = 220) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: size / out.extent.width, y: size / out.extent.height))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
