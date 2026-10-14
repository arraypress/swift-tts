//
//  KokoroFiles.swift
//  KokoroTTS
//
//  Created by David Sherlock on 2026.
//
//  Where FluidAudio keeps Kokoro, and whether all of it is there.
//
//  An engine reports `isReady` only after loading, so a caller asking
//  "can this run offline?" before loading heard "no" even with every file
//  on disk — `speak --no-download` refused an installed Kokoro. This answers
//  from the files alone, using FluidAudio's own lists of what it needs.
//

import FluidAudio
import Foundation

/// The files Kokoro runs from.
public enum KokoroFiles {

    /// FluidAudio's model root: `~/.cache/fluidaudio/Models` on a Mac.
    static var root: URL {
        // FluidAudio's own answer (it creates the folder if missing), with
        // its documented location as the fallback.
        let base = (try? TtsCacheDirectory.ensure())
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/fluidaudio")
        return base.appendingPathComponent("Models")
    }

    /// The seven CoreML stages, their vocabulary and the default voice.
    public static var modelDirectory: URL { root.appendingPathComponent(Repo.kokoroAne.folderName) }

    /// The neural G2P and Misaki's lexicons.
    public static var textDirectory: URL { root.appendingPathComponent(Repo.kokoro.folderName) }

    /// Everything a first run downloads, by folder.
    static var required: [(folder: URL, names: Set<String>)] {
        [
            (modelDirectory, ModelNames.KokoroAne.requiredModels),
            (textDirectory, ModelNames.G2P.requiredModels.union(
                MisakiLexicon.files(british: false) + MisakiLexicon.files(british: true))),
        ]
    }

    /// Whether every file Kokoro needs is on disk — so it can run with the
    /// network off. Voices other than `af_heart` are fetched on first use
    /// and are not counted.
    public static func isDownloaded() -> Bool {
        required.allSatisfy { folder, names in
            names.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        }
    }
}
