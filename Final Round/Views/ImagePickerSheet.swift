import SwiftUI
import PhotosUI
import UIKit

/// A reusable image picker that offers both camera and photo library options
struct ImagePickerSheet: View {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(AppTheme.textSecondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            Text("Add Photo")
                .font(AppTheme.font(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.bottom, 24)
            
            VStack(spacing: 12) {
                // Take Photo Button
                Button {
                    showingCamera = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(AppTheme.font(size: 22))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.lightGreen)
                            .clipShape(Circle())
                        
                        Text("Take Photo")
                            .font(AppTheme.font(size: 17, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(AppTheme.font(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(16)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
                
                // Choose from Library Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle")
                            .font(AppTheme.font(size: 22))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.lightGreen)
                            .clipShape(Circle())
                        
                        Text("Choose from Library")
                            .font(AppTheme.font(size: 17, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        
                        Spacer()
                        
                        if isLoadingPhoto {
                            ProgressView()
                                .tint(AppTheme.primary)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(AppTheme.font(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .padding(16)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .disabled(isLoadingPhoto)
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Cancel Button
            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(AppTheme.font(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(AppTheme.background)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraImagePicker(image: $selectedImage, isPresented: $showingCamera) {
                // Dismiss the sheet after camera finishes
                isPresented = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedImage) { _, newImage in
            if newImage != nil {
                isPresented = false
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                await loadPhoto(from: newItem)
            }
        }
    }
    
    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        await MainActor.run {
            isLoadingPhoto = true
        }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Crop to square for profile photos, then resize for faster uploads
                let squareImage = cropToSquare(image)
                let resizedImage = resizeImageForUpload(squareImage, maxDimension: 512)
                
                await MainActor.run {
                    self.selectedImage = resizedImage
                    self.isLoadingPhoto = false
                    self.isPresented = false
                }
            } else {
                await MainActor.run {
                    self.isLoadingPhoto = false
                }
            }
        } catch {
            print("❌ Failed to load photo: \(error)")
            await MainActor.run {
                self.isLoadingPhoto = false
            }
        }
    }
}

// MARK: - Camera Image Picker (UIKit wrapper)

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var isPresented: Bool
    var onImagePicked: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        
        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Prefer edited image (cropped), fall back to original
            let selectedImage = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            
            if let image = selectedImage {
                // Crop to square (center crop) for profile photos
                let squareImage = cropToSquare(image)
                // Resize for faster uploads
                parent.image = resizeImageForUpload(squareImage, maxDimension: 512)
            }
            
            parent.isPresented = false
            
            // Call completion handler after a short delay to ensure camera is dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                self.parent.onImagePicked?()
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Image Processing Helpers

/// Crops an image to a square from the center
func cropToSquare(_ image: UIImage) -> UIImage {
    let originalSize = image.size
    let shortestSide = min(originalSize.width, originalSize.height)
    
    // If already square, return as-is
    guard originalSize.width != originalSize.height else { return image }
    
    // Calculate crop rect (center of the image)
    let cropRect = CGRect(
        x: (originalSize.width - shortestSide) / 2,
        y: (originalSize.height - shortestSide) / 2,
        width: shortestSide,
        height: shortestSide
    )
    
    // Handle image orientation
    guard let cgImage = image.cgImage else { return image }
    
    // Apply the crop respecting image orientation
    let scale = image.scale
    let scaledRect = CGRect(
        x: cropRect.origin.x * scale,
        y: cropRect.origin.y * scale,
        width: cropRect.width * scale,
        height: cropRect.height * scale
    )
    
    guard let croppedCGImage = cgImage.cropping(to: scaledRect) else { return image }
    
    return UIImage(cgImage: croppedCGImage, scale: scale, orientation: image.imageOrientation)
}

/// Resizes an image to fit within the specified maximum dimension while maintaining aspect ratio
func resizeImageForUpload(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let size = image.size
    
    // Check if resizing is needed
    guard size.width > maxDimension || size.height > maxDimension else {
        return image
    }
    
    // Calculate new size maintaining aspect ratio
    let ratio = min(maxDimension / size.width, maxDimension / size.height)
    let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
    
    // Create resized image
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resizedImage = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    
    return resizedImage
}

#Preview {
    ImagePickerSheet(
        selectedImage: .constant(nil),
        isPresented: .constant(true)
    )
}

