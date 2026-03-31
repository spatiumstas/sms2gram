SHELL := /bin/bash
VERSION := $(shell cat VERSION)
PACKAGE := sms2gram
ROOT_DIR := /opt
DEPENDENCIES := curl, jq, ca-certificates, wget-ssl

.PHONY: clean _pkg-clean _pkg-control _pkg-scripts _pkg-ipk sms2gram-ipk

clean:
	rm -rf out/pkg

_pkg-clean:
	rm -rf out/$(BUILD_DIR)
	mkdir -p out/$(BUILD_DIR)/control
	mkdir -p out/$(BUILD_DIR)/data

_pkg-control:
	echo "Package: $(PACKAGE)" > out/$(BUILD_DIR)/control/control
	echo "Version: $(VERSION)" >> out/$(BUILD_DIR)/control/control
	echo "Depends: $(DEPENDENCIES)" >> out/$(BUILD_DIR)/control/control
	echo "Section: net" >> out/$(BUILD_DIR)/control/control
	echo "Architecture: all" >> out/$(BUILD_DIR)/control/control
	echo "License: MIT" >> out/$(BUILD_DIR)/control/control
	echo "URL: https://github.com/spatiumstas/sms2gram" >> out/$(BUILD_DIR)/control/control
	echo "Description: SMS to Telegram/VK/SMS forwarder" >> out/$(BUILD_DIR)/control/control

_pkg-scripts:
	cp common/ipk/postinst out/$(BUILD_DIR)/control/postinst
	cp common/ipk/conffiles out/$(BUILD_DIR)/control/conffiles
	cp common/ipk/postrm out/$(BUILD_DIR)/control/postrm
	find out/$(BUILD_DIR)/control -type f -print0 | xargs -0 dos2unix
	chmod +x out/$(BUILD_DIR)/control/postinst
	chmod +x out/$(BUILD_DIR)/control/postrm
	chmod +x out/$(BUILD_DIR)/control/conffiles

_pkg-ipk:
	make _pkg-clean
	make _pkg-control
	make _pkg-scripts
	cd out/$(BUILD_DIR)/control; tar czvf ../control.tar.gz .; cd ../../..

	mkdir -p out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram
	cp common/sms2gram.sh out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram/sms2gram.sh
	sed 's/^SCRIPT_VERSION=""/SCRIPT_VERSION="$(VERSION)"/' common/01-sms2gram.sh > out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram/01-sms2gram.sh
	cp common/config.sh out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram/config.sh
	find out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram -type f -print0 | xargs -0 dos2unix
	chmod +x out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram/sms2gram.sh
	chmod +x out/$(BUILD_DIR)/data$(ROOT_DIR)/root/sms2gram/01-sms2gram.sh
	cd out/$(BUILD_DIR)/data; tar czvf ../data.tar.gz .; cd ../../..

	echo 2.0 > out/$(BUILD_DIR)/debian-binary
	cd out/$(BUILD_DIR); \
	tar czvf ../$(PACKAGE)_$(VERSION).ipk control.tar.gz data.tar.gz debian-binary; \
	cd ../..

sms2gram-ipk:
	@make \
		BUILD_DIR=pkg \
		_pkg-ipk
