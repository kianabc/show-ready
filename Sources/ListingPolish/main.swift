#if os(macOS)
ListingPolishApp.main()
#else
// The app is macOS only. This lets `swift test` build the core module on Linux CI.
print("ListingPolish is a macOS app.")
#endif
