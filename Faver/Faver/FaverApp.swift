import SwiftUI
import UIKit

@main
struct FaverApp: App {
    init() {
        // Apply New York (slab serif) to navigation bar titles.
        // SwiftUI's .fontDesign() modifier cannot reach UIKit nav bar text,
        // so we set it via UINavigationBar.appearance() instead.
        if let largeDescriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.serif) {
            let bold = largeDescriptor.withSymbolicTraits(.traitBold) ?? largeDescriptor
            UINavigationBar.appearance().largeTitleTextAttributes = [
                .font: UIFont(descriptor: bold, size: 36)
            ]
        }
        if let inlineDescriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .headline)
            .withDesign(.serif) {
            let semibold = inlineDescriptor.withSymbolicTraits(.traitBold) ?? inlineDescriptor
            UINavigationBar.appearance().titleTextAttributes = [
                .font: UIFont(descriptor: semibold, size: 17)
            ]
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
