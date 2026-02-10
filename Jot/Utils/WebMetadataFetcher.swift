//
//  WebMetadataFetcher.swift
//  Jot
//
//  Created by AI on 01.09.25.
//
//  Utility to fetch website metadata and generate thumbnails

import Foundation
import SwiftUI
import WebKit
import Combine
import ObjectiveC

struct WebMetadata {
    let title: String
    let description: String
    let domain: String
    let url: String
    var thumbnail: NSImage?
}

@MainActor
class WebMetadataFetcher: ObservableObject {
    
    func fetchMetadata(from urlString: String, completion: @escaping (WebMetadata) -> Void) {
        guard let url = URL(string: urlString) else {
            let domain = urlString.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            completion(WebMetadata(title: "Invalid URL", description: "Could not load website", domain: domain, url: urlString))
            return
        }
        
        let domain = url.host ?? urlString
        
        // Fetch metadata + generate a visual preview (snapshot) of the page
        Task {
            // Attempt metadata; don't fail the whole flow if HTML parsing fails
            var metaTitle = domain.capitalized
            var metaDescription = "Visit \(domain)"
            do {
                let (title, description) = try await self.fetchBasicMetadata(from: url)
                if !title.isEmpty { metaTitle = title }
                if !description.isEmpty { metaDescription = description }
            } catch { /* ignore and use defaults */ }

            // Always attempt to get a preview image
            var thumbnail = await self.snapshotWithWebView(from: url)
            if thumbnail == nil {
                thumbnail = await self.fetchWebsiteScreenshot(from: urlString)
            }
            if let img = thumbnail { thumbnail = self.normalizePreview(img) }

            let metadata = WebMetadata(
                title: metaTitle,
                description: metaDescription,
                domain: domain,
                url: urlString,
                thumbnail: thumbnail
            )
            await MainActor.run {
                completion(metadata)
            }
        }
    }
    
    private func fetchBasicMetadata(from url: URL) async throws -> (title: String, description: String) {
        let request = URLRequest(url: url, timeoutInterval: 6.0)
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let htmlString = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        
        // Parse HTML for title and description
        let title = extractTitle(from: htmlString)
        let description = extractDescription(from: htmlString)
        
        return (title, description)
    }
    
    private func fetchWebsiteScreenshot(from urlString: String) async -> NSImage? {
        // Use a free screenshot service with reduced timeout for faster loading
        guard let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let screenshotURL = URL(string: "https://image.thum.io/get/width/400/crop/600/\(encodedURL)") else {
            return await fetchFavicon(from: urlString)
        }
        
        do {
            // Reduced timeout for faster fallback
            let request = URLRequest(url: screenshotURL, timeoutInterval: 8.0)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, 
               httpResponse.statusCode == 200,
               let image = NSImage(data: data) {
                return image
            }
        } catch {
            print("Screenshot fetch failed: \(error)")
        }
        
        // Fallback to favicon
        return await fetchFavicon(from: urlString)
    }

    // MARK: - WKWebView Snapshot (preferred when possible)
    private func snapshotWithWebView(from url: URL, size: CGSize = CGSize(width: 800, height: 520), timeout: TimeInterval = 8) async -> NSImage? {
        await MainActor.run(body: {}) // ensure MainActor
        return await withCheckedContinuation { continuation in
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = false
            config.defaultWebpagePreferences.preferredContentMode = .recommended
            config.mediaTypesRequiringUserActionForPlayback = [.video, .audio]
            
            let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
            webView.isHidden = true // off-screen
            #if os(macOS)
            // Attach to a transient window to ensure rendering pipeline produces a snapshot
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .popUpMenu
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.contentView = NSView(frame: CGRect(origin: .zero, size: size))
            window.contentView?.addSubview(webView)
            #endif

            var didResume = false
            let finish: (NSImage?) -> Void = { image in
                if didResume { return }
                didResume = true
                #if os(macOS)
                window.orderOut(nil)
                #endif
                continuation.resume(returning: image)
            }
            let loader = WebViewLoader { image in
                finish(image)
            }
            webView.navigationDelegate = loader
            
            // Attach the loader strongly to the webView via associated object so it stays alive
            objc_setAssociatedObject(webView, &WebViewLoader.AssociatedKeys.loader, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            webView.load(request)
            
            // Timeout guard
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if didResume { return }
                // Attempt a snapshot anyway if content rendered partially
                let snapConfig = WKSnapshotConfiguration()
                webView.takeSnapshot(with: snapConfig) { image, _ in
                    finish(image)
                }
            }
        }
    }

    private final class WebViewLoader: NSObject, WKNavigationDelegate {
        struct AssociatedKeys { static var loader = "webviewloader_assoc" }
        let completion: (NSImage?) -> Void
        init(completion: @escaping (NSImage?) -> Void) { self.completion = completion }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 1) Remove common page gutters via CSS and prevent video autoplay
            let css = "document.documentElement.style.margin='0';document.documentElement.style.padding='0';document.body.style.margin='0';document.body.style.padding='0';document.documentElement.style.overflow='hidden';"
            let style = "var s=document.createElement('style');s.innerHTML='html,body{max-width:100vw!important;}*{max-width:100vw!important;}::-webkit-scrollbar{display:none}video{display:none!important;}iframe[src*=\"youtube\"]{display:none!important;}';document.head.appendChild(s);"
            let preventAutoplay = "var videos=document.querySelectorAll('video');videos.forEach(v=>{v.pause();v.muted=true;v.autoplay=false;});var iframes=document.querySelectorAll('iframe');iframes.forEach(i=>{if(i.src.includes('youtube')||i.src.includes('vimeo')){i.style.display='none';}});"
            let js = css + style + preventAutoplay
            webView.evaluateJavaScript(js) { _, _ in
                // 2) Measure inner content to crop side gutters using WKSnapshotConfiguration.rect
                let measureJS = "(() => { const iw=window.innerWidth; const bw=document.body.clientWidth||document.documentElement.clientWidth||iw; const left=Math.max(0,(iw-bw)/2); return JSON.stringify({iw,bw,left,dpr:window.devicePixelRatio||1}); })();"
                webView.evaluateJavaScript(measureJS) { result, _ in
                    let config = WKSnapshotConfiguration()
                    config.afterScreenUpdates = true
                    if let json = result as? String,
                       let data = json.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let iw = dict["iw"] as? CGFloat,
                       let bw = dict["bw"] as? CGFloat,
                       let left = dict["left"] as? CGFloat,
                       let dpr = dict["dpr"] as? CGFloat,
                       iw > 0, bw > 0, dpr > 0 {
                        let leftPts = left / dpr
                        let widthPts = max(1, min(bw / dpr, webView.bounds.width))
                        let rect = CGRect(x: leftPts, y: 0, width: widthPts, height: webView.bounds.height)
                        config.rect = rect
                    }
                    // 3) Slight delay to allow paints and CSS to apply
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        webView.takeSnapshot(with: config) { [weak self] image, _ in
                            self?.completion(image)
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                self?.completion(image)
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                self?.completion(image)
            }
        }
    }

    // MARK: - Post-processing to reduce perceived side padding
    private func normalizePreview(_ image: NSImage) -> NSImage {
        // Crop 2% on all sides to standardize the bleed
        let cropPercentX: CGFloat = 0.02 // 2% each side
        let cropPercentY: CGFloat = 0.02 // 2% top/bottom

        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let insetX = w * cropPercentX
        let insetY = h * cropPercentY
        let rect = CGRect(x: insetX, y: insetY, width: max(1, w - 2*insetX), height: max(1, h - 2*insetY))
        guard let cropped = cg.cropping(to: rect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }
    
    private func fetchFavicon(from urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        
        let faviconURLs = [
            "https://\(host)/favicon.ico",
            "https://\(host)/favicon.png",
            "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
        ]
        
        for faviconURLString in faviconURLs {
            if let faviconURL = URL(string: faviconURLString) {
                do {
                    let request = URLRequest(url: faviconURL, timeoutInterval: 5.0)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 200,
                       let image = NSImage(data: data) {
                        return image
                    }
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    private func extractTitle(from html: String) -> String {
        // Extract title using regex
        let titleRegex = try! NSRegularExpression(pattern: "<title[^>]*>([^<]+)</title>", options: .caseInsensitive)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        if let match = titleRegex.firstMatch(in: html, options: [], range: range),
           let titleRange = Range(match.range(at: 1), in: html) {
            let title = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Limit title length to prevent overflow issues
            return String(title.prefix(80))
        }

        return ""
    }
    
    private func extractDescription(from html: String) -> String {
        // Try meta description first
        let descRegex = try! NSRegularExpression(pattern: "<meta[^>]*name=[\"']description[\"'][^>]*content=[\"']([^\"']+)[\"']", options: .caseInsensitive)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        if let match = descRegex.firstMatch(in: html, options: [], range: range),
           let descRange = Range(match.range(at: 1), in: html) {
            let description = String(html[descRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Limit description length to prevent overflow issues
            return String(description.prefix(150))
        }

        // Try og:description
        let ogDescRegex = try! NSRegularExpression(pattern: "<meta[^>]*property=[\"']og:description[\"'][^>]*content=[\"']([^\"']+)[\"']", options: .caseInsensitive)

        if let match = ogDescRegex.firstMatch(in: html, options: [], range: range),
           let descRange = Range(match.range(at: 1), in: html) {
            let description = String(html[descRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Limit description length to prevent overflow issues
            return String(description.prefix(150))
        }

        return ""
    }
}
