DERIVED := build
XCB := xcodebuild -project Drop.xcodeproj -scheme Drop -derivedDataPath $(DERIVED)

debug:
	$(XCB) -configuration Debug build && open "$(DERIVED)/Build/Products/Debug/Drop.app"

prod:
	$(XCB) -configuration Release build && open "$(DERIVED)/Build/Products/Release/Drop.app"

kill:
	-pkill -x Drop

clean:
	rm -rf $(DERIVED)

.PHONY: debug prod kill clean
