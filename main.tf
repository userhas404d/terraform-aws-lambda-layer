# create layer
# publish layer
# cleanup layer
# destroy layer

data "aws_region" "current" {}

locals {
  default_docker_commands = ["bash", "-c", "chmod +x layergen/create-layer.sh && ./layergen/create-layer.sh"]
  docker_commands         = concat(local.default_docker_commands, var.docker_commands)
  docker_image_name       = var.docker_image_name == "" ? "ldapmaint/layer" : var.docker_image_name

  module_path = abspath(path.module)

  dockerfile         = var.dockerfile == "" ? "${local.module_path}/bin/Dockerfile.layers" : var.dockerfile
  layer_build_script = var.layer_build_script == "" ? "${local.module_path}/bin/create-layer.sh" : var.layer_build_script

  # command that runs within the docker container to preform the layer creation steps
  layer_build_command = var.layer_build_command == "" ? "bash -c './bin/create-layer.sh'" : var.layer_build_command

  bindmount_root               = "/home/lambda-layer"
  layer_build_script_bindmount = ["${dirname(local.layer_build_script)}:${local.bindmount_root}/bin"]
  lambda_bindmount             = ["${var.target_lambda_path}:${local.bindmount_root}/${basename(var.target_lambda_path)}"]
  additional_docker_bindmounts = var.additional_docker_bindmounts == [] ? [] : var.additional_docker_bindmounts
  docker_bindmounts            = concat(local.layer_build_script_bindmount, local.lambda_bindmount, local.additional_docker_bindmounts)
}

module "create_layer" {
  source = "git::https://github.com/matti/terraform-shell-resource.git?ref=v1.0.7 "

  environment = {
    DOCKER_FILE_PATH   = local.dockerfile
    DOCKER_RUN_FLAGS   = "--rm"
    DOCKER_BINDMOUNTS  = "-v ${join(" -v ", local.docker_bindmounts)}"
    DOCKER_ENV_VARS    = ""
    DOCKER_WORKING_DIR = local.bindmount_root
    DOCKER_COMMAND     = "bash -c './bin/create-layer.sh'"

    AWS_DEFAULT_REGION = data.aws_region.current.name
    TARGET_LAMBDA_PATH = abspath(path.module)
    LAYER_ARCHIVE_NAME = "lambda_layer_payload.zip"

    LAYER_DESCRIPTION   = var.layer_description
    LAYER_NAME          = var.layer_name
    COMPATIBLE_RUNTIMES = join(" ", var.compatible_runtimes)
  }

  command              = "make layer/publish"
  command_when_destroy = "make layer/destroy"

  # runs on every apply
  trigger = timestamp()

  working_dir = "${path.module}/bin"
}

output "test" {
  value = file("${path.module}/layer_arn.txt")
}