#!/usr/bin/env swift
//
// Generates the app's four sound effects into SudokuApp/Resources/Sounds/.
//
//   swift scripts/make-sounds.swift
//
// The sounds are synthesised rather than recorded or licensed, and the script is
// committed rather than just its output, because a tone defined by a line of
// code can be adjusted; a 20 KB binary whose provenance is "someone made it
// once" cannot. Re-running this reproduces the files byte for byte.
//
// The palette is deliberately narrow: soft sine partials with fast exponential
// decay, nothing percussive, nothing that reads as an alert. This is a Sudoku
// app, and the sound of placing a digit is heard several hundred times a puzzle.

import AVFoundation
import Foundation

let sampleRate = 44_100.0

/// One partial of a tone: a frequency, how loud it starts, and how fast it dies.
struct Partial {
    let frequency: Double
    let amplitude: Double
    /// Seconds to decay to roughly a thousandth of the starting amplitude.
    let decay: Double
    /// Seconds from the start of the sound before this partial begins.
    var delay: Double = 0
}

/// Sums the partials into a mono buffer with a short fade in and out.
///
/// The 3 ms fade at each end is not shaping, it is hygiene: a waveform that
/// starts or stops at a non-zero sample clicks, and a click is the one thing
/// guaranteed to be noticed several hundred times a puzzle.
func render(_ partials: [Partial], duration: Double) -> [Float] {
    let count = Int(duration * sampleRate)
    var samples = [Float](repeating: 0, count: count)
    let fade = Int(0.003 * sampleRate)

    for partial in partials {
        let start = Int(partial.delay * sampleRate)
        guard start < count else { continue }
        for index in start..<count {
            let time = Double(index - start) / sampleRate
            let envelope = exp(-time / (partial.decay / 6.9))
            let value = sin(2 * .pi * partial.frequency * time) * partial.amplitude * envelope
            samples[index] += Float(value)
        }
    }

    for index in 0..<min(fade, count) {
        let gain = Float(index) / Float(fade)
        samples[index] *= gain
        samples[count - 1 - index] *= gain
    }

    // Normalise to a comfortable ceiling rather than to full scale: these play
    // over whatever else the phone is doing, and the loudest sound in the room
    // is not the one anybody wanted from a puzzle app.
    let peak = samples.map(abs).max() ?? 1
    if peak > 0 {
        let scale = Float(0.7) / peak
        for index in samples.indices { samples[index] *= scale }
    }
    return samples
}

func write(_ samples: [Float], to url: URL) throws {
    // swiftlint:disable:next force_unwrapping
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ],
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )

    // swiftlint:disable:next force_unwrapping
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    // swiftlint:disable:next force_unwrapping
    samples.withUnsafeBufferPointer { buffer.floatChannelData!.pointee.update(from: $0.baseAddress!, count: samples.count) }
    try file.write(from: buffer)
}

// The note the whole set is tuned around. A major triad and its octave, so
// nothing ever clashes with anything else the app might play at the same time.
let c6 = 1046.50
let e6 = 1318.51
let g6 = 1567.98
let c7 = 2093.00

let sounds: [(name: String, samples: [Float])] = [
    // Placing a digit: one soft partial with a touch of body under it. Short
    // enough to fire on every tap of a fast fill without becoming a rattle.
    (
        "place",
        render(
            [
                Partial(frequency: c6, amplitude: 0.8, decay: 0.05),
                Partial(frequency: c6 / 2, amplitude: 0.25, decay: 0.03),
            ],
            duration: 0.09
        )
    ),

    // A conflict: low, dull, two beats. Not a buzzer — the setting that turns
    // mistake highlighting on is opt-in, and the sound that goes with it should
    // read as "that one clashes", not as a failure.
    (
        "conflict",
        render(
            [
                Partial(frequency: 196, amplitude: 0.7, decay: 0.06),
                Partial(frequency: 164, amplitude: 0.5, decay: 0.08, delay: 0.06),
            ],
            duration: 0.2
        )
    ),

    // A row, column or box completed: two notes rising. The first thing in the
    // set that sounds like praise.
    (
        "unit",
        render(
            [
                Partial(frequency: e6, amplitude: 0.6, decay: 0.09),
                Partial(frequency: g6, amplitude: 0.6, decay: 0.14, delay: 0.07),
            ],
            duration: 0.28
        )
    ),

    // Solved: the triad, arpeggiated, with the octave on top. Long enough to
    // land under the win card's animation without outstaying it.
    (
        "solve",
        render(
            [
                Partial(frequency: c6, amplitude: 0.55, decay: 0.35),
                Partial(frequency: e6, amplitude: 0.55, decay: 0.35, delay: 0.09),
                Partial(frequency: g6, amplitude: 0.55, decay: 0.35, delay: 0.18),
                Partial(frequency: c7, amplitude: 0.6, decay: 0.5, delay: 0.27),
            ],
            duration: 0.8
        )
    ),
]

// From the script's own path rather than the working directory, so it can be run
// from anywhere and still write to the one place the files belong.
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let directory = root.appending(path: "SudokuApp/Resources/Sounds")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for sound in sounds {
    let url = directory.appending(path: "\(sound.name).caf")
    try? FileManager.default.removeItem(at: url)
    try write(sound.samples, to: url)
    let bytes = (try? Data(contentsOf: url).count) ?? 0
    print("\(sound.name).caf  \(String(format: "%.2f", Double(sound.samples.count) / sampleRate))s  \(bytes) bytes")
}
