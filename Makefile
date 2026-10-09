# Keystone / Denge Noktası — developer entry points.
SIM ?= iPhone 16
DEST := platform=iOS Simulator,name=$(SIM)
PROJECT := DengeNoktasi.xcodeproj
XCB := xcodebuild -project $(PROJECT) -destination '$(DEST)' CODE_SIGNING_ALLOWED=NO

FORGE_OUT ?= $(CURDIR)/forge-out
FORGE_COUNT ?= 1200
FORGE_SEED_BASE ?= 9000

.PHONY: bootstrap build test core-test physics-test forge-smoke forge-validate forge-pool forge-curated clean

bootstrap:
	./scripts/bootstrap.sh

build: bootstrap
	$(XCB) -scheme DengeNoktasi build

test: bootstrap
	$(XCB) -scheme DengeNoktasi test

# Pure logic, runs anywhere Swift 6 runs (macOS or Linux).
core-test:
	swift test --package-path Packages/BalanceCore

# Fast daily gate: curated levels, solution path only.
forge-smoke: bootstrap
	$(XCB) -scheme LevelForge test -only-testing:LevelForgeTests/ForgeRunner/testCuratedSmoke

# Release gate: re-verifies every shipped level and its engine fingerprint.
forge-validate: bootstrap
	$(XCB) -scheme LevelForge test -only-testing:LevelForgeTests/ForgeRunner/testValidateShippedLevels

# Offline pool generation. Env vars reach the test process through the TEST_RUNNER_ prefix.
forge-pool: bootstrap
	mkdir -p $(FORGE_OUT)
	TEST_RUNNER_FORGE_OUT=$(FORGE_OUT) TEST_RUNNER_FORGE_COUNT=$(FORGE_COUNT) TEST_RUNNER_FORGE_SEED_BASE=$(FORGE_SEED_BASE) \
	  $(XCB) -scheme LevelForge test -only-testing:LevelForgeTests/ForgeRunner/testGeneratePool

# Re-solves and re-annotates the curated drafts in Tools/LevelForge/drafts.
forge-curated: bootstrap
	mkdir -p $(FORGE_OUT)
	TEST_RUNNER_FORGE_OUT=$(FORGE_OUT) \
	  $(XCB) -scheme LevelForge test -only-testing:LevelForgeTests/ForgeRunner/testAnnotateCurated

clean:
	rm -rf $(PROJECT) DerivedData build Packages/*/.build
