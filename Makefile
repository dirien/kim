ifeq ($(GOARCH),)
GOARCH := $(shell go env GOARCH)
endif
GOARM := 7

ifeq ($(GOOS),)
GOOS := $(shell go env GOOS)
endif

DOCKER_BUILDKIT ?= 1
DOCKER_IMAGE    ?= docker image
DOCKER_MANIFEST ?= docker manifest

ORG ?= rancher
PKG ?= github.com/rancher/kim
TAG ?= $(shell git describe --tags --always)
IMG := $(ORG)/kim:$(subst +,-,$(TAG))

ifeq ($(GO_BUILDTAGS),)
GO_BUILDTAGS := static_build,netgo,osusergo
#ifeq ($(GOOS),linux)
#GO_BUILDTAGS := $(GO_BUILDTAGS),seccomp,selinux
#endif
endif

GO_LDFLAGS ?= -w -extldflags=-static
GO_LDFLAGS += -X $(PKG)/pkg/version.GitCommit=$(shell git rev-parse HEAD)
GO_LDFLAGS += -X $(PKG)/pkg/version.Version=$(TAG)
GO_LDFLAGS += -X $(PKG)/pkg/server.DefaultAgentImage=docker.io/$(ORG)/kim

GO ?= go
GOLANG ?= golang:1.16-alpine3.12

BIN ?= bin/kim
ifeq ($(GOOS),windows)
BINSUFFIX := .exe
endif
BIN := $(BIN)$(BINSUFFIX)

.PHONY: build image package publish validate
build: $(BIN)
package: | dist image
publish: | image image-push image-manifest
validate:

.PHONY: $(BIN)
$(BIN):
	$(GO) build -ldflags "$(GO_LDFLAGS)" -tags "$(GO_BUILDTAGS)" -o $@ .

.PHONY: dist
dist:
	@mkdir -p dist/artifacts
	@make GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) BIN=dist/artifacts/kim-$(GOOS)-$(GOARCH)$(BINSUFFIX) -C .

.PHONY: clean
clean:
	rm -rf bin dist vendor

.PHONY: image
image:
	DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) $(DOCKER_IMAGE) build \
		--build-arg GOLANG=$(GOLANG) \
		--build-arg ORG=$(ORG) \
		--build-arg PKG=$(PKG) \
		--build-arg TAG=$(TAG) \
		--tag $(IMG) \
		--tag $(IMG)-$(GOARCH) \
	.

.PHONY: image-push
image-push:
	$(DOCKER_IMAGE) push $(IMG)-$(GOARCH)

.PHONY: image-manifest
image-manifest:
	DOCKER_CLI_EXPERIMENTAL=enabled $(DOCKER_MANIFEST) create --amend \
		$(IMG) \
		$(IMG)-$(GOARCH)
	DOCKER_CLI_EXPERIMENTAL=enabled $(DOCKER_MANIFEST) push \
		$(IMG)

.PHONY: image-manifest-all
image-manifest-all:
	DOCKER_CLI_EXPERIMENTAL=enabled $(DOCKER_MANIFEST) create --amend \
		$(IMG) \
		$(IMG)-amd64 \
		$(IMG)-arm64 \
		$(IMG)-arm
	DOCKER_CLI_EXPERIMENTAL=enabled $(DOCKER_MANIFEST) annotate \
		--arch arm \
		--variant v$(GOARM) \
		$(IMG) \
		$(IMG)-arm
	DOCKER_CLI_EXPERIMENTAL=enabled $(DOCKER_MANIFEST) push \
		$(IMG)

# use this target to test drone builds locally
.PHONY: drone-local
drone-local:
	DRONE_TAG=v0.0.0-dev.0+drone drone exec --trusted

.PHONY: dogfood
dogfood: build
	DOCKER_IMAGE="./bin/kim image" make image

.PHONY: symlinks
symlinks: build
	ln -nsf $(notdir $(BIN)) $(dir $(BIN))/kubectl-builder
	ln -nsf $(notdir $(BIN)) $(dir $(BIN))/kubectl-image
