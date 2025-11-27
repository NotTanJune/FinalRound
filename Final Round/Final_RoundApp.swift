//
//  Final_RoundApp.swift
//  Final Round
//
//  Created by Tanmay Nargas on 23/11/25.
//

import SwiftUI
import CoreData

// This file no longer declares an @main App to avoid duplicate entry points.
// It only exposes the shared PersistenceController for use elsewhere if needed.

struct CoreDataEnvironmentProvider: ViewModifier {
    let persistenceController = PersistenceController.shared

    func body(content: Content) -> some View {
        content.environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
}

extension View {
    func withCoreDataContext() -> some View {
        self.modifier(CoreDataEnvironmentProvider())
    }
}
