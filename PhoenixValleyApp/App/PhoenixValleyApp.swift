import SwiftUI

@main
struct PhoenixValleyApp: App {
    @State private var document = RoadDocumentStore()
    @State private var intentRouter = AppIntentRouter.shared

    var body: some Scene {
        WindowGroup {
            RoadEditorView(document: document)
                .onAppear(perform: handlePendingIntent)
                .onChange(of: intentRouter.request) {
                    handlePendingIntent()
                }
        }
    }

    @MainActor
    private func handlePendingIntent() {
        guard let request = intentRouter.consumeRequest() else { return }
        if request.createsNewMap {
            document.createNewMap()
        }
        if let kind = request.roadKind {
            document.activateDrawing(kind: kind)
        }
    }
}
