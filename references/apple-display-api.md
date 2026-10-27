# API references checked 2026-10-27

- https://developer.apple.com/documentation/coregraphics/cgconfiguredisplaywithdisplaymode(_:_:_:_:)
  Public configuration transaction API; CGBeginDisplayConfiguration + configure + CGCompleteDisplayConfiguration.
- https://developer.apple.com/documentation/coregraphics/cgdisplaymode/pixelwidth
  Backing pixels are distinct from mode logical width.
- Local SDK: CoreGraphics.framework/Headers/CGDisplayConfiguration.h: kCGConfigureForSession=1, configuration transaction cancellation and automatic app/session restoration semantics.

The app enumerates existing system modes using public CoreGraphics. Generating scale-resolutions is a separate reconstructed, undocumented configuration format. The generated set is compared against the live model-specific override; no claim of portability to other models/OS versions.
