#if os(macOS)
ShowreadyApp.main()
#else
// The app is macOS only. This lets `swift test` build the core module on Linux CI.
print("Showready is a macOS app.")
#endif
