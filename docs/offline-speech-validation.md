# Offline speech cancellation and cache

The previous implementation started one 8 MiB-stack Thread per request, then
blocked these threads on SpeechWorker's lock. Cancelling the Swift Task did not
cancel those queued syntheses or release its continuation. This is a confirmed
source-level lifetime/queue issue, not evidence of an observed device stall.

SpeechScheduler now shares one engine across reader instances, runs at most one
synthesis, and retains at most one latest pending request. Replaced/cancelled
requests resume exactly once with CancellationError. Cancelled pending requests
are removed; an active request is checked before/after backend work and before
cache publication. PDFReaderModel retains its playbackID and Task cancellation
checks, and uses injectable SpeechProviding for controlled tests.

The vendored KokoroEngine.synthesize API is synchronous. Cancellation cannot
interrupt model loading, tokenization, or an in-flight Core ML prediction (or
its remaining internal chunks). One obsolete synthesis may continue until that
call returns, and the newest request waits for it. No Thread termination or
Core ML interruption is claimed. Using streaming/chunk-level cancellation is a
possible future change, outside this minimum fix.

PageAudio remains in Application Support so existing cached audio is reused.
The worker prunes owned WAV files on requests and after writes, using last
access modification time and a 128 MiB soft limit. The returned file is protected
from eviction in that pass; a single oversized page can exceed the limit until
the next different request. Cleanup is best effort and does not turn speech
into an error. Cancelled synthesis results normally are discarded before write;
cancellation racing the final atomic move can still leave a reusable cache file.
There is no timer/startup sweep: cleanup occurs when speech is requested.

## Automated validation

Tests in PDFStudyTests.swift include:
- a gated, non-interruptible mock with 50 rapidly cancelled page requests;
- active cancellation returning before the synthesis gate is released;
- pending replacement (only first/latest synthesize), close/reopen, and recovery
  from a backend error;
- a reader mock that intentionally completes despite cancellation, checking
  repeated clicks, rapid turns, late success/error, and close;
- oldest-first cache eviction, protected/oversized files, unrelated-file safety.

Run on a Mac with the project's supported Xcode and installed iPad simulator:

```sh
xcodebuild -project BilingualVideo.xcodeproj -scheme BilingualVideo \
  -destination 'platform=iOS Simulator,id=<installed-iPad-simulator-UDID>' \
  -only-testing:BilingualVideoTests/LocalSpeechTaskTests \
  -only-testing:BilingualVideoTests/PDFStudyTests test
```

Then run BilingualVideoUITests/PDFStudyUITests for the existing interaction
regression coverage. In the implementation environment (Linux), xcodebuild and
Swift are absent; the tests have been added but were not executed. Only
`git diff --check` was run successfully. Compilation and test success remain
required before merging.

## Device acceptance (airplane mode, representative supported iPad)

1. Cold model: repeatedly tap, turn through 50 pages while requesting speech,
   close during synthesis, and reopen immediately. Repeat with a warm engine.
2. Confirm no old page starts playing, no error from stale work appears, and
   controls remain responsive. Latest speech may wait for one old synthesis.
3. Profile Threads, Allocations, CPU and Energy with Instruments. Confirm no
   accumulation of waiting speech threads/reader objects and only one synthesis
   at a time; measure cancellation-to-UI-idle and latest-speech latency.
4. Repeat with long text and low-memory pressure; model memory remains shared
   for app lifetime, so measure its retained footprint and thermal behavior.
5. Populate more than 128 MiB of valid cached WAVs, request more pages, and
   confirm pruning, successful current playback, cache reuse, and behavior with
   low disk space. Check protection for an oversized current page.

Mock tests do not establish Core ML throughput, UI frame rate, memory pressure,
thermal behavior, or real-device audio-session correctness.
