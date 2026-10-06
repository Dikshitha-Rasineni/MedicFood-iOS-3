import SwiftUI

/// A medicine's photo, or a clean pill placeholder when there isn't one.
/// Never shows a broken-image symbol.
struct MedicineThumbnail: View {
    var fileName: String?
    var form: MedicineForm = .tablet
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = MediaStore.image(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.Colors.surface.opacity(0.6)
                    Image(systemName: form.symbolName)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }
}
