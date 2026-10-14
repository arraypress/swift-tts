//
//  QuantizationTable.swift
//  DramaTTS
//
//  Created by David Sherlock on 2026.
//
//  mlx-lm's `quantization` block: `group_size` and `bits` as the default, and
//  an object per layer path that differs (this checkpoint: experts 4-bit,
//  everything else 8-bit).
//

import Foundation

/// The checkpoint's quantisation settings.
struct QuantizationTable: Decodable, Sendable {

    /// One layer's settings.
    struct Setting: Decodable, Sendable, Equatable {
        /// Weights per scale.
        var groupSize: Int
        /// Bits per weight.
        var bits: Int

        enum CodingKeys: String, CodingKey {
            case groupSize = "group_size"
            case bits
        }
    }

    /// The default.
    var standard: Setting
    /// Per-path overrides.
    var layers: [String: Setting]

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(standard: Setting, layers: [String: Setting]) {
        self.standard = standard
        self.layers = layers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        standard = Setting(groupSize: try c.decode(Int.self, forKey: AnyKey(stringValue: "group_size")),
                           bits: try c.decode(Int.self, forKey: AnyKey(stringValue: "bits")))
        var layers: [String: Setting] = [:]
        for key in c.allKeys where key.stringValue != "group_size" && key.stringValue != "bits" {
            if let setting = try? c.decode(Setting.self, forKey: key) { layers[key.stringValue] = setting }
        }
        self.layers = layers
    }
}
