import SwiftUI

struct FoodImageView: View {
    var size: CGFloat = 48

    var body: some View {
        Image("apple")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
