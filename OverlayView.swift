import SwiftUI

/// 画面上の「浮遊オーバーレイ」配置を統一するコンテナ
/// - 目的：Toast/✅/InfoOverlay などの位置ブレ・重なり事故を根絶する
struct OverlayView<Content: View>: View {

    enum Position {
        case topLeading
        case top
        case topTrailing
        case center
        case bottomLeading
        case bottom
        case bottomTrailing
    }

    let position: Position
    let paddingTop: CGFloat
    let paddingLeading: CGFloat
    let paddingBottom: CGFloat
    let paddingTrailing: CGFloat

    @ViewBuilder let content: () -> Content

    init(
        position: Position,
        paddingTop: CGFloat = 12,
        paddingLeading: CGFloat = 12,
        paddingBottom: CGFloat = 12,
        paddingTrailing: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.position = position
        self.paddingTop = paddingTop
        self.paddingLeading = paddingLeading
        self.paddingBottom = paddingBottom
        self.paddingTrailing = paddingTrailing
        self.content = content
    }

    var body: some View {
        ZStack {
            switch position {
            case .topLeading:
                VStack { HStack { content(); Spacer() }.padding(.top, paddingTop).padding(.leading, paddingLeading); Spacer() }
            case .top:
                VStack { HStack { Spacer(); content(); Spacer() }.padding(.top, paddingTop); Spacer() }
            case .topTrailing:
                VStack { HStack { Spacer(); content() }.padding(.top, paddingTop).padding(.trailing, paddingTrailing); Spacer() }
            case .center:
                VStack { Spacer(); HStack { Spacer(); content(); Spacer() }; Spacer() }
            case .bottomLeading:
                VStack { Spacer(); HStack { content(); Spacer() }.padding(.bottom, paddingBottom).padding(.leading, paddingLeading) }
            case .bottom:
                VStack { Spacer(); HStack { Spacer(); content(); Spacer() }.padding(.bottom, paddingBottom) }
            case .bottomTrailing:
                VStack { Spacer(); HStack { Spacer(); content() }.padding(.bottom, paddingBottom).padding(.trailing, paddingTrailing) }
            }
        }
        .allowsHitTesting(false)
    }
}
