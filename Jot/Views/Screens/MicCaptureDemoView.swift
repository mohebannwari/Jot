import SwiftUI

struct MicCaptureDemoView: View {
    @State private var lastResult: MicCaptureControl.Result?

    var body: some View {
        VStack(spacing: 24) {
            MicCaptureControl(onSend: handleSend) {
                lastResult = nil
            }
            .frame(maxWidth: 360)

            if let result = lastResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last capture")
                        .font(.headline)
                    Text("File: \(result.audioURL.lastPathComponent)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let transcript = result.transcript {
                        Text("Transcript: \(transcript)")
                            .font(.body)
                    } else {
                        Text("No transcript available.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 360)
    }

    private func handleSend(result: MicCaptureControl.Result) {
        lastResult = result
    }
}

#if DEBUG
struct MicCaptureDemoView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MicCaptureDemoView()
                .preferredColorScheme(.light)
            MicCaptureDemoView()
                .preferredColorScheme(.dark)
        }
    }
}
#endif
