-include ./bin/Makefile

# DOCKER_FILE_PATH ?= $(shell pwd)/Dockerfile.layers
# DOCKER_RUN_FLAGS := --rm
# DOCKER_BINDMOUNTS := -v $(shell pwd):/layer_creation
# DOCKER_ENV_VARS := 
# DOCKER_WORKING_DIR = /layer_creation
# DOCKER_COMMAND = bash -c './bin/create-layer.sh'


# AWS_DEFAULT_REGION ?= us-east-1
# LAYER_ARCHIVE_NAME ?= lambda_layer_payload.zip
# LAYER_ARCHIVE_FULL_PATH := $(TARGET_LAMBDA_PATH)/$(LAYER_ARCHIVE_NAME)