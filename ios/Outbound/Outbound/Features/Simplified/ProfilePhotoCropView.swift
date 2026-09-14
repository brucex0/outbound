import SwiftUI
import UIKit

struct ProfilePhotoCropView: View {
    let onCancel: () -> Void
    let onUsePhoto: (UIImage) -> Void

    @State private var sourceImage: UIImage
    @State private var committedScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @State private var cropSide: CGFloat = 1
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1

    private let maximumScale: CGFloat = 4

    init(
        image: UIImage,
        onCancel: @escaping () -> Void,
        onUsePhoto: @escaping (UIImage) -> Void
    ) {
        self.onCancel = onCancel
        self.onUsePhoto = onUsePhoto
        _sourceImage = State(initialValue: image.normalizedForProfileCrop())
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = max(1, min(proxy.size.width - 32, proxy.size.height - 112))

                VStack(spacing: OutboundSpacing.standard) {
                    Spacer(minLength: OutboundSpacing.compact)

                    cropCanvas(side: side)
                        .frame(width: side, height: side)
                        .onAppear { cropSide = side }
                        .onChange(of: side) { _, newSide in
                            cropSide = newSide
                            committedOffset = constrainedOffset(
                                committedOffset,
                                scale: committedScale,
                                side: newSide
                            )
                        }

                    Text(String(
                        localized: "profile.photo.crop.help",
                        defaultValue: "Move and zoom to frame your photo"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack(spacing: OutboundSpacing.standard) {
                        Button {
                            sourceImage = sourceImage.rotatedClockwiseForProfileCrop()
                            committedScale = 1
                            committedOffset = .zero
                        } label: {
                            Image(systemName: "rotate.right")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(String(
                            localized: "profile.photo.crop.rotate",
                            defaultValue: "Rotate"
                        ))

                        Image(systemName: "minus.magnifyingglass")
                            .accessibilityHidden(true)

                        Slider(value: $committedScale, in: 1...maximumScale)
                            .onChange(of: committedScale) { _, newScale in
                                committedOffset = constrainedOffset(
                                    committedOffset,
                                    scale: newScale,
                                    side: cropSide
                                )
                            }
                            .accessibilityLabel(String(
                                localized: "profile.photo.crop.zoom",
                                defaultValue: "Zoom"
                            ))

                        Image(systemName: "plus.magnifyingglass")
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, OutboundSpacing.screen)

                    Spacer(minLength: OutboundSpacing.compact)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(OutboundPalette.background)
            .navigationTitle(String(
                localized: "profile.photo.crop.title",
                defaultValue: "Crop Photo"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save", defaultValue: "Save")) {
                        guard let croppedImage = croppedImage(side: cropSide) else { return }
                        onUsePhoto(croppedImage)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func cropCanvas(side: CGFloat) -> some View {
        let scale = effectiveScale
        let offset = constrainedOffset(
            CGSize(
                width: committedOffset.width + dragTranslation.width,
                height: committedOffset.height + dragTranslation.height
            ),
            scale: scale,
            side: side
        )
        let displaySize = displayedImageSize(scale: scale, side: side)

        return ZStack {
            Color.black

            Image(uiImage: sourceImage)
                .resizable()
                .frame(width: displaySize.width, height: displaySize.height)
                .offset(offset)

            ProfilePhotoCropMask()
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

            Circle()
                .strokeBorder(.white.opacity(0.92), lineWidth: 2)
                .padding(1)
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(cropGesture(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            localized: "profile.photo.crop.title",
            defaultValue: "Crop Photo"
        ))
    }

    private func cropGesture(side: CGFloat) -> some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                committedOffset = constrainedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    scale: effectiveScale,
                    side: side
                )
            }

        let magnify = MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                committedScale = min(maximumScale, max(1, committedScale * value))
                committedOffset = constrainedOffset(
                    committedOffset,
                    scale: committedScale,
                    side: side
                )
            }

        return drag.simultaneously(with: magnify)
    }

    private var effectiveScale: CGFloat {
        min(maximumScale, max(1, committedScale * gestureScale))
    }

    private func displayedImageSize(scale: CGFloat, side: CGFloat) -> CGSize {
        let imageSize = sourceImage.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: side, height: side)
        }
        let aspectFillScale = max(side / imageSize.width, side / imageSize.height)
        return CGSize(
            width: imageSize.width * aspectFillScale * scale,
            height: imageSize.height * aspectFillScale * scale
        )
    }

    private func constrainedOffset(_ offset: CGSize, scale: CGFloat, side: CGFloat) -> CGSize {
        let displaySize = displayedImageSize(scale: scale, side: side)
        let maximumX = max(0, (displaySize.width - side) / 2)
        let maximumY = max(0, (displaySize.height - side) / 2)
        return CGSize(
            width: min(maximumX, max(-maximumX, offset.width)),
            height: min(maximumY, max(-maximumY, offset.height))
        )
    }

    private func croppedImage(side: CGFloat) -> UIImage? {
        guard side > 0, let cgImage = sourceImage.cgImage else { return nil }
        let imageSize = sourceImage.size
        let scale = committedScale
        let offset = constrainedOffset(committedOffset, scale: scale, side: side)
        let displayScale = max(side / imageSize.width, side / imageSize.height) * scale
        let displayedSize = displayedImageSize(scale: scale, side: side)
        let origin = CGPoint(
            x: (side - displayedSize.width) / 2 + offset.width,
            y: (side - displayedSize.height) / 2 + offset.height
        )
        let sourceRect = CGRect(
            x: -origin.x / displayScale,
            y: -origin.y / displayScale,
            width: side / displayScale,
            height: side / displayScale
        ).intersection(CGRect(origin: .zero, size: imageSize))

        guard sourceRect.width > 0,
              sourceRect.height > 0,
              let croppedCGImage = cgImage.cropping(to: sourceRect) else { return nil }

        let outputSize = CGSize(width: 1_024, height: 1_024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            UIImage(cgImage: croppedCGImage).draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }
}

private struct ProfilePhotoCropMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
        return path
    }
}

extension UIImage {
    func normalizedForProfileCrop() -> UIImage {
        guard size.width > 0, size.height > 0 else { return self }
        let maximumDimension: CGFloat = 4_096
        let resizeScale = min(1, maximumDimension / max(size.width, size.height))
        let outputSize = CGSize(
            width: size.width * resizeScale,
            height: size.height * resizeScale
        )
        guard imageOrientation != .up || scale != 1 || resizeScale < 1 else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: outputSize))
        }
    }

    func rotatedClockwiseForProfileCrop() -> UIImage {
        let rotatedSize = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: rotatedSize, format: format).image { context in
            context.cgContext.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            ))
        }
    }
}
