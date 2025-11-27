   import SwiftUI

   struct TagFlowLayout<Content: View>: View {
       let spacing: CGFloat
       let alignment: HorizontalAlignment
       @ViewBuilder let content: () -> Content

       init(spacing: CGFloat = 8,
            alignment: HorizontalAlignment = .leading,
            @ViewBuilder content: @escaping () -> Content) {
           self.spacing = spacing
           self.alignment = alignment
           self.content = content
       }

       var body: some View {
           FlowLayoutContainer(spacing: spacing, alignment: alignment, content: content)
       }
   }

   private struct FlowLayoutContainer<Content: View>: View {
       let spacing: CGFloat
       let alignment: HorizontalAlignment
       @ViewBuilder let content: () -> Content

       var body: some View {
           GeometryReader { proxy in
               let availableWidth = proxy.size.width
               _FlowRows(availableWidth: availableWidth,
                         spacing: spacing,
                         alignment: alignment,
                         content: content)
           }
       }
   }

   private struct _FlowRows<Content: View>: View {
       let availableWidth: CGFloat
       let spacing: CGFloat
       let alignment: HorizontalAlignment
       @ViewBuilder let content: () -> Content

       var body: some View {
           let views = content().asArray()
           var rows: [[AnyView]] = []
           var currentRow: [AnyView] = []
           var currentRowWidth: CGFloat = 0

           // Measure each view by hosting it invisibly to get its ideal size
           ForEachMeasured(views: views) { measured in
               let width = measured.size.width

               if currentRow.isEmpty {
                   currentRow = [measured.view]
                   currentRowWidth = width
               } else if currentRowWidth + spacing + width <= availableWidth {
                   currentRow.append(measured.view)
                   currentRowWidth += spacing + width
               } else {
                   rows.append(currentRow)
                   currentRow = [measured.view]
                   currentRowWidth = width
               }
           } rowsCompletion: {
               if !currentRow.isEmpty {
                   rows.append(currentRow)
               }
           }
           .overlay(
               VStack(alignment: alignment, spacing: spacing) {
                   ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                       HStack(spacing: spacing) {
                           ForEach(Array(row.enumerated()), id: \.offset) { _, view in
                               view
                           }
                       }
                       .frame(maxWidth: .infinity, alignment: .leading)
                   }
               }
           )
           .hidden() // hide measuring layer; overlay displays actual layout
       }
   }

   // Helpers to measure child views

   private struct MeasuredView: Identifiable {
       let id = UUID()
       let view: AnyView
       let size: CGSize
   }

   private struct ForEachMeasured: View {
       let views: [AnyView]
       let content: (MeasuredView) -> Void
       let rowsCompletion: () -> Void

       init(views: [AnyView],
            content: @escaping (MeasuredView) -> Void,
            rowsCompletion: @escaping () -> Void) {
           self.views = views
           self.content = content
           self.rowsCompletion = rowsCompletion
       }

       var body: some View {
           ZStack {
               ForEach(Array(views.enumerated()), id: \.offset) { index, view in
                   SizeReader {
                       content(MeasuredView(view: view, size: $0))
                       if index == views.count - 1 {
                           rowsCompletion()
                       }
                   } content: {
                       view
                   }
                   .fixedSize()
                   .opacity(0.0)
               }
           }
       }
   }

   private struct SizeReader<Content: View>: View {
       let onSize: (CGSize) -> Void
       @ViewBuilder let content: () -> Content

       init(_ onSize: @escaping (CGSize) -> Void,
            content: @escaping () -> Content) {
           self.onSize = onSize
           self.content = content
       }

       var body: some View {
           content()
               .background(
                   GeometryReader { proxy in
                       Color.clear
                           .preference(key: SizePreferenceKey.self, value: proxy.size)
                   }
               )
               .onPreferenceChange(SizePreferenceKey.self, perform: onSize)
       }
   }

   private struct SizePreferenceKey: PreferenceKey {
       static var defaultValue: CGSize = .zero
       static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
           value = nextValue()
       }
   }

   // Convert variadic content to array of AnyView
   private extension View {
       func eraseToAnyView() -> AnyView { AnyView(self) }
   }

   private extension View {
       func asArray() -> [AnyView] {
           // Wrap in TupleView extractor
           if let tuple = Mirror(reflecting: self).children.first?.value {
               return TupleViewExtractor.extract(from: tuple).map { $0.eraseToAnyView() }
           }
           return [eraseToAnyView()]
       }
   }

   private enum TupleViewExtractor {
       static func extract(from value: Any) -> [AnyView] {
           let mirror = Mirror(reflecting: value)
           var result: [AnyView] = []
           for child in mirror.children {
               if let view = child.value as? any View {
                   result.append(AnyView(view))
               }
           }
           return result
       }
   }
