import AVFoundation
import Foundation

public enum SpeakTool {

    /// 0.5 ~ 2.0 → 映射到系统语速倍率
    public static func rate(_ raw: String) -> Float {
        let v = (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).floatValue
        let clamped = min(max(v == 0 ? 1.0 : v, 0.4), 2.0)
        return clamped * Float(AVSpeechUtteranceDefaultSpeechRate)
    }

    public static func utterance(_ text: String, rate: Float) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = rate
        u.preUtteranceDelay = 0.1
        return u
    }

    @MainActor
    public static func speak(_ text: String, rate rawRate: String, timeout: TimeInterval = 180) async -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return FilesTool.err("朗读内容为空") }

        let synth = AVSpeechSynthesizer()
        let box = FinishBox()
        synth.delegate = box

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
            box.finishIfNeeded()
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            // 先挂上 continuation，再开始朗读：避免「读完还没挂上」导致永久等待
            box.attach(c)
            synth.speak(utterance(t, rate: rate(rawRate)))
        }
        timeoutTask.cancel()
        return FilesTool.ok(["spoken": t, "rate": String(rate(rawRate))])
    }
}

/// 把 AVSpeechSynthesizer 回调桥接到 Swift 并发，且幂等（完成/超时都只会 resume 一次）
final class FinishBox: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    /// 挂载 continuation；若朗读已提前结束则立即恢复
    func attach(_ c: CheckedContinuation<Void, Never>) {
        if finished {
            c.resume()
            return
        }
        continuation = c
    }

    func finishIfNeeded() {
        guard !finished else { return }
        finished = true
        continuation?.resume()
        continuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishIfNeeded()
    }
}
