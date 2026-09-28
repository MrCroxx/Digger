.DEFAULT_GOAL := help
ifeq ($(DIGGER_MAC_UNSIGNED),1)
export SIGN_IDENTITY ?=
else
export SIGN_IDENTITY ?= auto
endif

.PHONY: help dev build release dmg test

help:
	@echo "make dev      编译并打开 Debug 应用"
	@echo "make build    只编译 Debug 应用"
	@echo "make release  检查、编译、签名 Release 应用并打包 DMG / ZIP"
	@echo "make dmg      同 make release"
	@echo "make test     运行 Swift 测试"
	@echo "产物位于 dist/；签名默认自动选择唯一证书，可设置 SIGN_IDENTITY=证书名称"
	@echo "无证书时使用临时签名；也可显式设置 DIGGER_MAC_UNSIGNED=1"

# Open only after a successful build, never an old artifact after failure.
dev: build
	@. ./scripts/build-config.sh; open "dist/$$APP_NAME.app"

build:
	BUILD_CONFIGURATION=debug CREATE_DMG=0 CREATE_ZIP=0 ./scripts/build-app.sh

release:
	BUILD_CONFIGURATION=release CREATE_DMG=1 CREATE_ZIP=1 ./scripts/package-desktop.sh

dmg: release

test:
	swift test
