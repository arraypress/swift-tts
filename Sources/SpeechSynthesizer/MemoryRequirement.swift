//
//  MemoryRequirement.swift
//  SpeechSynthesizer
//
//  Created by David Sherlock on 2026.
//
//  The least memory a Mac-class model is allowed to start on — measured per
//  model, never guessed — and the comparison against this Mac's.
//

import Foundation

/// A floor on physical memory, below which an engine refuses to start.
public struct MemoryRequirement: Sendable, Equatable {

    /// The floor, in bytes as `hw.memsize` reports them.
    public let minimumBytes: UInt64

    /// - Parameter gigabytes: The floor in GiB, as Macs are sold.
    public init(gigabytes: UInt64) {
        self.minimumBytes = gigabytes * 1_073_741_824
    }

    /// The shortfall on a Mac with `physicalMemory` bytes, in GiB, or nil
    /// when it has enough.
    public func shortfall(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory)
        -> (physicalGB: Double, requiredGB: Double)? {
        guard physicalMemory < minimumBytes else { return nil }
        return (Double(physicalMemory) / 1_073_741_824, Double(minimumBytes) / 1_073_741_824)
    }
}
