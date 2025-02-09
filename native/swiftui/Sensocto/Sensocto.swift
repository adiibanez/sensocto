//
//  Sensocto.swift
//  Sensocto
//
import SwiftUI

@main
struct Sensocto: App {
    
    #if os(iOS)
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    
    #endif
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
