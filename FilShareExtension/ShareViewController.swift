//
//  ShareViewController.swift
//  FilShareExtension
//
//  Created by Mason Garcera on 6/30/26.
//

import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        // Attachments (a shared URL or image) can carry the content on their own,
        // so an empty note field is still valid.
        return true
    }

    override func didSelectPost() {
        let note = contentText ?? ""

        extractSharedContent { [weak self] extractedText, images in
            let combinedText = [note, extractedText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            SharedDraftInbox.append(text: combinedText, imageData: images)

            // Inform the host that we're done so it un-blocks its UI.
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    // MARK: - Attachment extraction

    private func extractSharedContent(completion: @escaping (String, [Data]) -> Void) {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        var texts: [String] = []
        var images: [Data] = []
        let group = DispatchGroup()

        for provider in attachments {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { texts.append(url.absoluteString) }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                group.enter()
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    if let text { texts.append(text) }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                _ = provider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let data = (image as? UIImage)?.pngData() { images.append(data) }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion(texts.joined(separator: "\n"), images)
        }
    }
}
