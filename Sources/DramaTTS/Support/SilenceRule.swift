//
//  SilenceRule.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Stop-on-dead-air, with thresholds MEASURED on 18 probe clips (Python and
//  Swift), per 1 s window: level, and the spread of its 50 ms sub-window
//  levels. A runaway chunk does not go silent — it hisses, steadily, at −34 to
//  −81 dBFS, and every hiss window had a spread of at most 1.2 dB. Speech,
//  whispered speech included, never spread less than 2.9 dB, and quiet speech
//  (below −30 dBFS) never less than 5.0. Level alone cannot tell them apart:
//  whispers reached −44 dBFS and one runaway hissed at −37. So a window is dead
//  air when it is quieter than −45 dBFS, or quieter than −30 dBFS and flatter
//  than 2.5 dB. The longest legitimate pause measured was 1.0 s; 2 s of dead
//  air is a runaway. (A false alarm costs a resample, not lost audio: the
//  pipeline rewinds to the last speech rather than giving up.)
//

import Foundation

/// When generated audio has stopped being speech.
struct SilenceRule: Sendable, Equatable {

    /// Quieter than this, in dBFS, is dead air whatever its shape.
    var silenceDB: Float = -45

    /// Quieter than this, in dBFS, and flat, is dead air (steady hiss).
    var quietDB: Float = -30

    /// A spread of 50 ms levels below this, in dB, is flat.
    var flatSpreadDB: Float = 2.5

    /// Sub-window length for the spread, in seconds.
    var subWindow: Double = 0.05

    /// Dead air this long, in seconds, is a runaway.
    var maximumQuiet: Double = 2.0

    /// Dead air kept at the end of a stopped chunk, in seconds.
    var keptTail: Double = 0.5
}
