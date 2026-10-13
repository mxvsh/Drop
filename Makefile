DERIVED := build
XCB := xcodebuild -project Drop.xcodeproj -scheme Drop -derivedDataPath $(DERIVED)

debug:
	$(XCB) -configuration Debug build && open "$(DERIVED)/Build/Products/Debug/Drop Debug.app"

prod:
	$(XCB) -configuration Release build && open "$(DERIVED)/Build/Products/Release/Drop.app"

kill:
	-pkill -x "Drop Debug"
	-pkill -x Drop

# Prints the Sparkle public key, creating the key pair in your login keychain on first run.
# Back up the private key: `$(SPARKLE_BIN)/generate_keys --account drop -x drop-sparkle.key`
SPARKLE_BIN := $(DERIVED)/SourcePackages/artifacts/sparkle/Sparkle/bin
sparkle-key:
	@test -x "$(SPARKLE_BIN)/generate_keys" || $(XCB) -resolvePackageDependencies >/dev/null
	"$(SPARKLE_BIN)/generate_keys" --account drop

clean:
	rm -rf $(DERIVED)

.PHONY: debug prod kill clean sparkle-key
