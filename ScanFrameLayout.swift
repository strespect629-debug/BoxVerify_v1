import SwiftUI

@MainActor
struct ScanFrameLayout<
    InstructionCard: View,
    BottomTitle: View,
    BottomOverlay: View,
    FloatingOverlay: View
>: View {

    @ObservedObject var cameraManager: CameraManager

    let guideCenterYOffset: CGFloat
    let cardTopPadding: CGFloat
    let bottomOverlayPadding: CGFloat

    @ViewBuilder let instructionCard: () -> InstructionCard
    @ViewBuilder let bottomTitle: () -> BottomTitle
    @ViewBuilder let bottomOverlay: () -> BottomOverlay
    @ViewBuilder let floatingOverlay: () -> FloatingOverlay

    init(
        cameraManager: CameraManager,
        guideCenterYOffset: CGFloat,
        cardTopPadding: CGFloat = 140,
        bottomOverlayPadding: CGFloat = 84,
        @ViewBuilder instructionCard: @escaping () -> InstructionCard,
        @ViewBuilder bottomTitle: @escaping () -> BottomTitle,
        @ViewBuilder bottomOverlay: @escaping () -> BottomOverlay,
        @ViewBuilder floatingOverlay: @escaping () -> FloatingOverlay
    ) {
        self.cameraManager = cameraManager
        self.guideCenterYOffset = guideCenterYOffset
        self.cardTopPadding = cardTopPadding
        self.bottomOverlayPadding = bottomOverlayPadding
        self.instructionCard = instructionCard
        self.bottomTitle = bottomTitle
        self.bottomOverlay = bottomOverlay
        self.floatingOverlay = floatingOverlay
    }

    var body: some View {
        ZStack {
            CameraPreviewView(
                manager: cameraManager,
                guideCenterYOffset: guideCenterYOffset
            )
            .ignoresSafeArea()

            if let err = cameraManager.cameraError, !err.isEmpty {
                CameraPermissionOverlay(cameraError: err)
            } else {
                VStack {
                    instructionCard()
                        .padding(.top, cardTopPadding)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 18)
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    bottomOverlay()
                        .padding(.bottom, bottomOverlayPadding)
                }
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack {
                        bottomTitle()
                            .padding(.leading, 18)
                        Spacer()
                    }
                    .padding(.bottom, 16)
                }
                .allowsHitTesting(false)

                floatingOverlay()
                    .allowsHitTesting(true)
            }
        }
    }
}
