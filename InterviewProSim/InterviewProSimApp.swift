//
//  InterviewProSimApp.swift
//  InterviewProSim
//
//  Created by Tanmay Nargas on 04/11/25.
//

import SwiftUI
import CoreData

@main
struct InterviewProSimApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
