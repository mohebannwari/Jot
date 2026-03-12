import SwiftUI

public struct ToggleSectionView: View {
    @Binding var isExpanded: Bool
    var title: String = "Toggle section"
    
    public init(isExpanded: Binding<Bool>, title: String = "Toggle section") {
        self._isExpanded = isExpanded
        self.title = title
    }
    
    public var body: some View {
        Button(action: {
            withAnimation(.snappy) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.7))
                
                Image("IconChevronRightMedium")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
