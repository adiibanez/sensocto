#if os(iOS)

import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ app: NSApplication, open urls: [URL]) {
        print("Received URLs: \(urls)")
    }
}

#endif
