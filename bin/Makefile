ARCH ?= amd64
CURL ?= curl --fail -sSL
XARGS ?= xargs -I {}
BIN_DIR ?= ${HOME}/bin
TMP ?= /tmp
PROJECT_ROOT ?= $(shell pwd)
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c

PATH := $(BIN_DIR):${PATH}

# publish layer
# cleanup layer
# destroy layer

guard/env/%:
	@ _="$(or $($*),$(error Make/environment variable '$*' not present))"

guard/program/%:
	@ which $* > /dev/null || $(MAKE) $*/install

$(BIN_DIR):
	@ echo "[make]: Creating directory '$@'..."
	mkdir -p $@

zip/install:
	@ echo "[$@]: Installing $(@D)..."
	apt-get install zip -y
	@ echo "[$@]: Completed successfully!"

docker/%: IMAGE_NAME := $(shell basename $(PROJECT_ROOT)):latest

## Builds the tardigrade-ci docker image
docker/build: GET_IMAGE_ID := docker inspect --type=image -f '{{.Id}}' "$(IMAGE_NAME)" 2> /dev/null || true
docker/build: IMAGE_ID ?= $(shell $(GET_IMAGE_ID))
docker/build: DOCKER_BUILDKIT ?= $(shell [ -z $(TRAVIS) ] && echo "DOCKER_BUILDKIT=1" || echo "DOCKER_BUILDKIT=0";)
docker/build:
	@echo "[$@]: building docker image"
	[ -n "$(IMAGE_ID)" ] && echo "Image present" || \
	$(DOCKER_BUILDKIT) docker build -t $(IMAGE_NAME) -f $(DOCKER_FILE_PATH) .
	@echo "[$@]: Docker image build complete"

# Adds the current Makefile working directory as a bind mount
## Runs the tardigrade-ci docker image
docker/run: docker/build
	@echo "[$@]: Running docker image"
	docker run $(DOCKER_RUN_FLAGS) $(DOCKER_BINDMOUNTS) $(DOCKER_ENV_VARS) -w $(DOCKER_WORKING_DIR) \
	$(IMAGE_NAME) $(DOCKER_COMMAND)

## Cleans local docker environment
docker/clean:
	@echo "[$@]: Cleaning docker environment"
	docker image prune -a -f
	docker system prune -a -f
	@echo "[$@]: cleanup successful"

layer/%: LAYER_ARCHIVE_NAME ?= lambda_layer_payload.zip
layer/%: LAYER_ARCHIVE_FULL_PATH ?= $(TARGET_LAMBDA_PATH)/$(LAYER_ARCHIVE_NAME)
layer/%: LAYER_ARN_FILE ?= $(TARGET_LAMBDA_PATH)/layer_arn.txt

layer/create: docker/build
layer/create: docker/run
layer/create:
	@ echo "[$@]: Layer creation complete!"

layer/publish: guard/program/jq
layer/publish: CREATE_LAYER ?= $(shell [ ! -f $(LAYER_ARCHIVE_FULL_PATH) ] && echo "$(MAKE) layer/create")
layer/publish:
	@ echo "[$@]: Publishing layer"
	$(CREATE_LAYER)
	aws lambda publish-layer-version \
	--layer-name $(LAYER_NAME) \
	--description "$(LAYER_DESCRIPTION)" \
	--zip-file fileb://$(LAYER_ARCHIVE_FULL_PATH) \
	--compatible-runtimes $(COMPATIBLE_RUNTIMES) | jq -r '.LayerVersionArn' > $(LAYER_ARN_FILE)
	@ echo "[$@]: Layer publishing complete"

layer/destroy: LAYER_ARN ?= $(shell cat $(LAYER_ARN_FILE))
layer/destroy: LAYER_BASE_ARN ?= $(shell echo $(LAYER_ARN) | sed 's/.\{2\}$$//')
layer/destroy: 
	@ echo "[$@]: Deleting layer"
	bash $(shell pwd)/delete-layer.sh $(LAYER_BASE_ARN)
	@ echo "[$@]: Layer deletion complete"