import AVKit
import Photos
import SwiftUI

/// A video in the review pager. Shows the poster frame with a play control until the
/// user asks for it, then plays inline.
///
/// Videos were being fetched into the queue all along and rendered through the still
/// image path, so they appeared as a frozen frame with nothing to say they were videos
/// and no way to watch them. You cannot judge a video from one frame, which left only
/// favoriting blind or skipping.
///
/// Deliberately not autoplaying. The review loop is a photo at a time at the user's own
/// pace, often in bed or on a bus; video that starts itself, with sound, is exactly the
/// kind of thing that makes an app unpleasant to open.
struct VideoReviewView: View {
    let asset: PHAsset

    @State private var poster: UIImage? = nil
    @State private var player: AVPlayer? = nil
    @State private var isPreparing = false

    var body: some View {
        ZStack {
            Color.black

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                posterLayer
            }
        }
        .ignoresSafeArea()
        .task(id: asset.localIdentifier) {
            // Exact: the poster fills the screen and nothing replaces it later, so it
            // cannot settle for whatever cached rendition happens to be nearest.
            poster = await PhotoImage.request(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                allowsNetwork: false,
                resize: .exact
            )
        }
        // Leaving the page stops playback. Without this the sound of a video follows the
        // user into the next photo.
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var posterLayer: some View {
        ZStack {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .scaledToFit()
            }

            Button { Task { await prepareAndPlay() } } label: {
                ZStack {
                    if isPreparing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                            .offset(x: 2) // optical centring of the triangle
                    }
                }
                .frame(width: 72, height: 72)
            }
            .glassEffect(.regular.interactive(), in: Circle())
            .disabled(isPreparing)
            .accessibilityLabel(isPreparing ? "Loading video" : "Play video, \(durationLabel)")

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(durationLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                        // The play control already announces the length.
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 130) // clear of the favorite button
            }
        }
    }

    private var durationLabel: String {
        let total = Int(asset.duration.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func prepareAndPlay() async {
        isPreparing = true
        defer { isPreparing = false }
        guard let item = await Self.playerItem(for: asset) else { return }
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        avPlayer.play()
    }

    /// Network access is allowed here, unlike the still-image first pass, because the
    /// user has explicitly asked to watch this one and is waiting on purpose.
    private static func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let manager = PHImageManager.default()
        nonisolated(unsafe) var requestID: PHImageRequestID?

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AVPlayerItem?, Never>) in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .automatic
                nonisolated(unsafe) var done = false
                requestID = manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                    guard !done else { return }
                    done = true
                    continuation.resume(returning: item)
                }
            }
        } onCancel: {
            if let requestID { manager.cancelImageRequest(requestID) }
        }
    }
}
