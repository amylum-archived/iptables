PACKAGE = iptables
ORG = amylum

DEP_DIR = /tmp/dep-dir

BUILD_DIR = /tmp/$(PACKAGE)-build
RELEASE_DIR = /tmp/$(PACKAGE)-release
RELEASE_FILE = /tmp/$(PACKAGE).tar.gz
PATH_FLAGS = --prefix=/usr --sbindir=/usr/bin --libexecdir=/usr/lib/iptables --sysconfdir=/etc
CONF_FLAGS = --enable-static --disable-shared --with-pic
CFLAGS = -static -static-libgcc -Wl,-static -lc -I$(DEP_DIR)/usr/include

PACKAGE_VERSION = $$(git --git-dir=upstream/.git describe --tags | sed 's/v//')
PATCH_VERSION = $$(cat version)
VERSION = $(PACKAGE_VERSION)-$(PATCH_VERSION)

LIBNFTNL_VERSION = 1.0.5-3
LIBNFTNL_URL = https://github.com/amylum/libnftnl/releases/download/$(LIBNFTNL_VERSION)/libnftnl.tar.gz
LIBNFTNL_TAR = /tmp/libnftnl.tar.gz
LIBNFTNL_DIR = /tmp/libnftnl
LIBNFTNL_PATH = -I$(LIBNFTNL_DIR)/usr/include -L$(LIBNFTNL_DIR)/usr/lib

.PHONY : default submodule deps manual container build version push local

default: submodule container

submodule:
	git submodule update --init

manual: submodule
	./meta/launch /bin/bash || true

container:
	./meta/launch

deps:
	mkdir -p $(DEP_DIR)/usr/include/
	cp -R /usr/include/{linux,asm,asm-generic} $(DEP_DIR)/usr/include/
	rm -rf $(LIBNFTNL_DIR) $(LIBNFTNL_TAR)
	mkdir $(LIBNFTNL_DIR)
	curl -sLo $(LIBNFTNL_TAR) $(LIBNFTNL_URL)
	tar -x -C $(LIBNFTNL_DIR) -f $(LIBNFTNL_TAR)

build: submodule deps
	rm -rf $(BUILD_DIR)
	cp -R upstream $(BUILD_DIR)
	cd $(BUILD_DIR) && ./autogen.sh
	cd $(BUILD_DIR) && CC=musl-gcc CFLAGS='$(CFLAGS) $(LIBNFTNL_PATH)' ./configure $(PATH_FLAGS) $(CONF_FLAGS)
	patch -p1 -d $(BUILD_DIR) < patches/iptables-musl-fixes.patch
	cd $(BUILD_DIR) && make && make DESTDIR=$(RELEASE_DIR) install
	rm -r $(RELEASE_DIR)/usr/lib/xtables
	mkdir -p $(RELEASE_DIR)/usr/share/licenses/$(PACKAGE)
	cp $(BUILD_DIR)/COPYING $(RELEASE_DIR)/usr/share/licenses/$(PACKAGE)/LICENSE
	cd $(RELEASE_DIR) && tar -czvf $(RELEASE_FILE) *

version:
	@echo $$(($(PATCH_VERSION) + 1)) > version

push: version
	git commit -am "$(VERSION)"
	ssh -oStrictHostKeyChecking=no git@github.com &>/dev/null || true
	git tag -f "$(VERSION)"
	git push --tags origin master
	@sleep 3
	targit -a .github -c -f $(ORG)/$(PACKAGE) $(VERSION) $(RELEASE_FILE)
	@sha512sum $(RELEASE_FILE) | cut -d' ' -f1

local: build push

