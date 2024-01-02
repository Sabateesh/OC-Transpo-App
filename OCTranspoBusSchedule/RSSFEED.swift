//
//  RSSFEED.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2024-01-01.
//

import Foundation
import Combine
import WebKit
import SwiftUI


struct RSSItem: Identifiable {
    let id = UUID()
    let title: String
    let pubDate: String
    let description: String
    let link: String
}

struct WebView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlContent, baseURL: nil)
    }
}

class RSSFeedViewModel: ObservableObject {
    @Published var rssItems: [RSSItem] = []

    func fetchRSSFeed() {
        guard let url = URL(string: "https://www.octranspo.com/en/feeds/updates-en/") else {
            print("Invalid URL")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                let parser = XMLParser(data: data)
                let rssParserDelegate = RSSParserDelegate()
                parser.delegate = rssParserDelegate
                if parser.parse() {
                    DispatchQueue.main.async {
                        self.rssItems = rssParserDelegate.rssItems
                    }
                }
            } else if let error = error {
                print("Error fetching RSS feed: \(error)")
            }
        }

        task.resume()
    }
}

class RSSParserDelegate: NSObject, XMLParserDelegate {
    var rssItems: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle: String = "" {
        didSet { currentTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var currentPubDate: String = "" {
        didSet { currentPubDate = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var currentDescription: String = "" {
        didSet { currentDescription = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var currentLink: String = "" {
        didSet { currentLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    private var isItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" {
            isItem = true
        }
        currentElement = elementName
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isItem {
            switch currentElement {
            case "title": currentTitle += string
            case "pubDate": currentPubDate += string
            case "description": currentDescription += string
            case "link": currentLink += string
            default: break
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let rssItem = RSSItem(title: currentTitle, pubDate: currentPubDate, description: currentDescription, link: currentLink)
            rssItems.append(rssItem)
            isItem = false
            currentTitle = ""
            currentPubDate = ""
            currentDescription = ""
            currentLink = ""
        }
    }
}

