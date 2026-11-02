.PHONY: build test run install release clean

build:
	./scripts/bundle.sh

test:
	./scripts/lint-design.sh
	./scripts/swift.sh test

run: build
	-pkill -x ThreeApp
	open build/Three.app

install:
	CONFIG=release ./scripts/bundle.sh
	-pkill -x ThreeApp
	rm -rf ~/Applications/Three.app
	mkdir -p ~/Applications
	cp -R build/Three.app ~/Applications/Three.app
	mkdir -p ~/.local/bin
	ln -sf ~/Applications/Three.app/Contents/Helpers/three ~/.local/bin/three
	open ~/Applications/Three.app

clean:
	rm -rf .build build
