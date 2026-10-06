This directory contains the unmodified library sources from Jud/kokoro-coreml
v0.11.2 (6bfc02afb237a311caee927482e58c028edb6acb), Apache-2.0.
Source: https://github.com/Jud/kokoro-coreml/tree/v0.11.2

Only Package.swift is adapted: retain the library and bundled resources, omit
CLI/test dependencies, pin BARTG2P 0.4.0, and declare an empty default trait.
The trait declaration avoids Xcode 27 package resolution rejecting the remote
package's removed traits. No runtime source has been modified.
