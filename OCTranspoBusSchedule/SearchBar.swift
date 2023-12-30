//
//  SearchBar.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-12-28.
//

import SwiftUI
import MapKit

struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    var searchCompleter: MKLocalSearchCompleter

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UISearchBarDelegate {
        var parent: SearchBar

        init(_ searchBar: SearchBar) {
            self.parent = searchBar
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
            parent.searchCompleter.queryFragment = searchText
        }
    }
}
