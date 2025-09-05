import SwiftUI

struct QRCodeView: View {
    var url: String

    var body: some View {
        if let qrCode = generateQRCode(from: url) {
            Image(uiImage: convertCIImageToUIImage(ciImage: qrCode))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Text("Generating QR Code failed.")
        }
    }

    private func generateQRCode(from string: String) -> CIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        if let output = filter.outputImage?.transformed(by: transform) {
            return output
        }
        return nil
    }

    private func convertCIImageToUIImage(ciImage: CIImage) -> UIImage {
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    QRCodeView(url: "hello")
}
