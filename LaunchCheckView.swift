import SwiftUI

struct LaunchCheckView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)

                Text("BoxVerify 起動確認")
                    .font(.title2)
                    .foregroundColor(.black)
            }
        }
    }
}
