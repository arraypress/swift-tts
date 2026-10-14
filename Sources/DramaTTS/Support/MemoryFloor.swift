//
//  MemoryFloor.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  Measured on an M3 Max with 36 GB: the 4-bit model holds 22 GB of weights;
//  the process peaks at 25.8 GB (29.4 GB in the Python reference, 29.2 GB here
//  before MLX's buffer cache was capped) — a 32 GB Mac, with the system and a
//  browser beside it, would swap on every clip. 36 GB is the smallest Mac it
//  has been measured to run on, so it is the floor.
//

import Foundation
import SpeechSynthesizer

/// The least memory Drama 3 is allowed to start on.
enum MemoryFloor {

    /// 36 GB.
    static let requirement = MemoryRequirement(gigabytes: 36)

    /// 36 GB, as `hw.memsize` reports it.
    static var minimumBytes: UInt64 { requirement.minimumBytes }

    /// The refusal for this Mac, or nil when it has enough.
    static func problem(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> DramaError? {
        requirement.shortfall(physicalMemory: physicalMemory).map {
            .insufficientMemory(physicalGB: $0.physicalGB, requiredGB: $0.requiredGB)
        }
    }
}
