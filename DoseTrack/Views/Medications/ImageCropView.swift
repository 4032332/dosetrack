// DoseTrack/Views/Medications/ImageCropView.swift
// A lightweight, dependency-free crop screen. E-Scripts are added as full phone screenshots, so
// this lets the user trim to just the QR code + relevant text (or keep the whole thing). A
// movable/resizable rectangle over the image; "Crop" returns the trimmed image, "Use Original"
// returns it untouched.

import SwiftUI
import UIKit

/// Identifiable wrapper so a pending image can drive `.fullScreenCover(item:)`.
struct CropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ImageCropView: View {
    let image: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    // Crop rect + the frame the image is actually drawn in, both in the container's view space.
    @State private var cropRect: CGRect = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var didInit = false

    private let handleSize: CGFloat = 28
    private let minCrop: CGFloat = 60

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(
                            GeometryReader { imgGeo in
                                Color.clear.onAppear {
                                    // scaledToFit centres the image; compute its drawn rect so the
                                    // crop rect and the final pixel mapping share one coordinate space.
                                    imageFrame = fittedRect(imageSize: image.size, in: imgGeo.size)
                                    if !didInit {
                                        cropRect = imageFrame.insetBy(dx: imageFrame.width * 0.08,
                                                                      dy: imageFrame.height * 0.08)
                                        didInit = true
                                    }
                                }
                            }
                        )

                    if didInit {
                        cropOverlay
                    }
                }
            }
            .navigationTitle("Crop E-Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) {
                    Button("Use Original") { onConfirm(image) }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crop") { onConfirm(croppedImage()) }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Crop overlay (dim outside + movable/resizable rect)

    private var cropOverlay: some View {
        ZStack {
            // Dim everything outside the crop rect.
            Rectangle()
                .fill(.black.opacity(0.55))
                .reverseMask { Rectangle().frame(width: cropRect.width, height: cropRect.height).position(x: cropRect.midX, y: cropRect.midY) }
                .allowsHitTesting(false)

            // The crop rectangle: draggable body + four corner handles.
            Rectangle()
                .stroke(.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture)

            ForEach(Corner.allCases, id: \.self) { corner in
                Circle()
                    .fill(.white)
                    .frame(width: handleSize, height: handleSize)
                    .position(handlePosition(corner))
                    .gesture(resizeGesture(corner))
            }
        }
    }

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private func handlePosition(_ corner: Corner) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight:    return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft:  return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }

    @State private var dragStartRect: CGRect? = nil

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let base = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = cropRect }
                var r = base.offsetBy(dx: value.translation.width, dy: value.translation.height)
                r.origin.x = min(max(r.origin.x, imageFrame.minX), imageFrame.maxX - r.width)
                r.origin.y = min(max(r.origin.y, imageFrame.minY), imageFrame.maxY - r.height)
                cropRect = r
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = dragStartRect ?? cropRect
                if dragStartRect == nil { dragStartRect = cropRect }
                var minX = base.minX, minY = base.minY, maxX = base.maxX, maxY = base.maxY
                let tx = value.translation.width, ty = value.translation.height
                switch corner {
                case .topLeft:     minX = base.minX + tx; minY = base.minY + ty
                case .topRight:    maxX = base.maxX + tx; minY = base.minY + ty
                case .bottomLeft:  minX = base.minX + tx; maxY = base.maxY + ty
                case .bottomRight: maxX = base.maxX + tx; maxY = base.maxY + ty
                }
                minX = max(minX, imageFrame.minX); minY = max(minY, imageFrame.minY)
                maxX = min(maxX, imageFrame.maxX); maxY = min(maxY, imageFrame.maxY)
                if maxX - minX >= minCrop, maxY - minY >= minCrop {
                    cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                }
            }
            .onEnded { _ in dragStartRect = nil }
    }

    // MARK: - Geometry / cropping

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Map the crop rect (view space) back into image-pixel space and crop.
    private func croppedImage() -> UIImage {
        guard imageFrame.width > 0 else { return image }
        // Work in the image's oriented (display) size, then account for scale to pixels.
        let displaySize = image.size
        let scaleX = displaySize.width / imageFrame.width
        let scaleY = displaySize.height / imageFrame.height
        let rectInImage = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )
        // Normalise a possibly-rotated source by rendering upright first, then crop in pixel space.
        let renderer = UIGraphicsImageRenderer(size: displaySize)
        let upright = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: displaySize)) }
        guard let uprightCG = upright.cgImage else { return image }
        let pxScale = CGFloat(uprightCG.width) / displaySize.width
        let pxRect = CGRect(x: rectInImage.minX * pxScale, y: rectInImage.minY * pxScale,
                            width: rectInImage.width * pxScale, height: rectInImage.height * pxScale)
            .integral
        guard let cropped = uprightCG.cropping(to: pxRect) else { return image }
        return UIImage(cgImage: cropped, scale: upright.scale, orientation: .up)
    }
}

// A reverse mask (punch a hole) helper — dims outside the crop rect.
private extension View {
    @ViewBuilder
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay(mask().blendMode(.destinationOut))
        }
    }
}
