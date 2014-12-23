LISP ?= sbcl
DEBUILD = /tmp/lispkit
APP_NAME = lispkit
PKG_NAME = lispkit-browser
DEPLOY_HOST = zerolength.com
DEPLOY_DIR = /srv/http/bin
SCP_DEPLOY = $(DEPLOY_HOST):$(DEPLOY_DIR)
SOURCES := $(wildcard *.lisp)
PKGBUILD_FILE = PKGBUILD
PKGVER=$(shell grep -oP 'pkgver=\K([0-9]+)' $(PKGBUILD_FILE))
PKGREL=$(shell grep -oP 'pkgrel=\K([0-9]+)' $(PKGBUILD_FILE))
AURBALL= $(PKG_NAME)-$(PKGVER)-$(PKGREL).src.tar.gz
QUICKLISP_SCRIPT=http://beta.quicklisp.org/quicklisp.lisp
QL_LOCAL=$(PWD)/.quicklocal/quicklisp
LOCAL_OPTS=--no-sysinit --no-userinit
sbcl_BUILD_OPTS=--load ./make-image.lisp
sbcl_BUILD_OPTS-local=$(LOCAL_OPTS) --load $(QL_LOCAL)/setup.lisp --load ./make-image.lisp
clisp_BUILD_OPTS=-on-error exit < ./make-image.lisp
sbcl_TEST_OPTS=--noinform --disable-debugger --quit --load ./run-tests.lisp


.PHONY: all test

all: $(APP_NAME)

local: local-quicklisp clones deps buildapp

clones: $(QL_LOCAL)/local-projects/cl-xkeysym \
		$(QL_LOCAL)/local-projects/cl-webkit;

$(QL_LOCAL)/local-projects/cl-xkeysym:
	git clone https://github.com/AeroNotix/cl-xkeysym.git $@

$(QL_LOCAL)/local-projects/cl-webkit:
	git clone https://github.com/joachifm/cl-webkit $@

deploy: $(APP_NAME).tar.gz
	rsync -a $< $(SCP_DEPLOY)

deb-package: $(APP_NAME)_debian.tar.gz
	fpm -s tar -t deb $<

aur-package: deploy
	sed -i 's/:md5sum/$(shell md5sum $(APP_NAME).tar.gz | cut -d' ' -f1)/g' $(PKGBUILD_FILE) && \
		makepkg -sf && \
		mkaurball -f && \
		burp $(AURBALL) && \
		git checkout $(PKGBUILD_FILE)

$(APP_NAME): $(SOURCES)
	@$(LISP) $($(LISP)_BUILD_OPTS)

$(APP_NAME)-local: $(SOURCES)
	@$(LISP) $($(LISP)_BUILD_OPTS-local)

$(QL_LOCAL)/setup.lisp:
	curl -O $(QUICKLISP_SCRIPT)
	sbcl $(LOCAL_OPTS) \
		--load quicklisp.lisp \
		--eval '(quicklisp-quickstart:install :path "$(QL_LOCAL)")' \
		--eval '(quit)'

local-quicklisp: $(QL_LOCAL)/setup.lisp

deps: $(QL_LOCAL)/setup.lisp clones
	sbcl $(LOCAL_OPTS) --load $(QL_LOCAL)/setup.lisp     \
             --eval '(push "$(PWD)/" asdf:*central-registry*)'  \
             --eval '(ql:quickload :lispkit)'                   \
             --eval '(quit)'
	touch $@

buildapp: $(QL_LOCAL)/setup.lisp deps clones
	buildapp --logfile /tmp/build.log               \
			--sbcl sbcl                             \
			--asdf-path .                           \
			--asdf-tree $(QL_LOCAL)/local-projects  \
			--asdf-tree $(QL_LOCAL)/dists           \
			--asdf-path .                           \
			--load-system $(APP_NAME)               \
			--entry $(APP_NAME):do-main             \
			--output lispkit

test:
	@$(LISP) $($(LISP)_TEST_OPTS)

tar: $(APP_NAME).tar.gz

$(APP_NAME).tar.gz: lispkit
	tar zcvf $@ lispkit

$(APP_NAME)_debian.tar.gz: lispkit
	mkdir -p ./opt/sbin/
	cp lispkit ./opt/sbin/
	tar zcvf $@ -C ./opt/sbin/ lispkit
