import SwiftUI

struct VaultManageView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack {
            Text("볼트 관리")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
