import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.965, green: 0.957, blue: 0.937, alpha: 1)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.text = L.t("shareExt.saving")
        label.translatesAutoresizingMaskIntoConstraints = false
        let done = UIButton(type: .system)
        done.setTitle(L.t("action.done"), for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label); view.addSubview(done)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            done.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            done.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        Task { await save() }
    }

    private func save() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved = 0
        for p in providers.prefix(3) {
            for (type, ext) in [(UTType.pdf, "pdf"), (UTType.image, "jpg")] where p.hasItemConformingToTypeIdentifier(type.identifier) {
                if let data = await load(p, type), !data.isEmpty, data.count < 30_000_000 {
                    let url = Store.inbox.appendingPathComponent("\(Date().timeIntervalSince1970)-\(saved).\(ext)")
                    if (try? data.write(to: url, options: .atomic)) != nil { saved += 1 }
                }
                break
            }
        }
        label.text = saved > 0 ? L.t("shareExt.saved") : L.t("shareExt.failed")
    }

    private func load(_ p: NSItemProvider, _ type: UTType) async -> Data? {
        await withCheckedContinuation { done in
            p.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in done.resume(returning: data) }
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
