locals {
  default_docker_commands = ["bash", "-c", "chmod +x layergen/create-layer.sh && ./layergen/create-layer.sh"]
  docker_commands         = concat(local.default_docker_commands, var.docker_commands)
  docker_image_name       = var.docker_image_name == "" ? "ldapmaint/layer" : var.docker_image_name

  module_path = abspath(path.module)

  dockerfile          = var.dockerfile == "" ? "${local.module_path}/bin/Dockerfile.layers" : var.dockerfile
  layer_build_script  = var.layer_build_script == "" ? "${local.module_path}/bin/create-layer.sh" : var.layer_build_script

  # command that runs within the docker container to preform the layer creation steps
  layer_build_command = var.layer_build_command == "" ? "bash -c './bin/create-layer.sh'" : var.layer_build_command

  bindmount_root               = "/home/lambda-layer"
  layer_build_script_bindmount = ["${dirname(local.layer_build_script)}:${local.bindmount_root}/bin"]
  lambda_bindmount             = ["${var.target_lambda_path}:${local.bindmount_root}/${basename(var.target_lambda_path)}"]
  additional_docker_bindmounts = var.additional_docker_bindmounts == [] ? [] : var.additional_docker_bindmounts
  docker_bindmounts            = concat(local.layer_build_script_bindmount, local.lambda_bindmount, local.additional_docker_bindmounts)
}

# check if the docker image exists on the current system
resource "null_resource" "docker_image_validate" {
  # re-run if the specified dockerfile changes
  triggers = {
    always_run = "${timestamp()}"
    working_dir = local.module_path
  }

  provisioner "local-exec" {
    command     = "${self.triggers.working_dir}/bin/docker-image-validate.sh"
    working_dir = self.triggers.working_dir
    environment = {
      DOCKERFILE = local.dockerfile
      IMAGE_NAME = local.docker_image_name
    }
  }
}

resource "null_resource" "create_layer" {

  depends_on = [
    null_resource.docker_image_validate
  ]

  triggers = {
    working_dir = local.module_path
  }

  provisioner "local-exec" {
    when        = create
    command     = "${self.triggers.working_dir}/bin/docker-run.sh"
    working_dir = self.triggers.working_dir
    environment = {
      BINDMOUNT_ROOT      = local.bindmount_root
      DOCKER_BINDMOUNTS   = jsonencode(local.docker_bindmounts)
      IMAGE_NAME          = local.docker_image_name
      LAYER_BUILD_COMMAND = local.layer_build_command
      LAYER_BUILD_SCRIPT  = local.layer_build_script
    }
  }
}

resource "random_uuid" "uuid" {
  depends_on = [null_resource.create_layer]
}

# borrowing patterns from here: https://github.com/matti/terraform-shell-resource
# waiting on working_dir and environment var support to be added before using the
# module directly
resource "null_resource" "publish_layer" {

  # depends_on = [
  #   null_resource.docker_image_validate,
  #   null_resource.create_layer
  # ]

triggers = {
  random_uuid = random_uuid.uuid.result
  working_dir = local.module_path
}

  provisioner "local-exec" {
    when        = create
    command     = "bin/publish-layer.sh 2>\"${local.module_path}/stderr.${self.triggers.random_uuid}\" >\"${local.module_path}/stdout.${self.triggers.random_uuid}\"; echo $? >\"${local.module_path}/exitstatus.${self.triggers.random_uuid}\""
    working_dir = path.module
    environment = {
      LAYER_NAME          = var.layer_name
      LAYER_DESCRIPTION   = var.layer_description
      COMPATIBLE_RUNTIMES = jsonencode(var.compatible_runtimes)
      LAYER_ARCHIVE_NAME  = "lambda_layer_payload.zip"
      TARGET_LAMBDA_PATH  = var.target_lambda_path
    }
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "rm \"stdout.${self.triggers.random_uuid}\""
    on_failure = continue
    working_dir = path.module
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "rm \"stderr.${self.triggers.random_uuid}\""
    on_failure = continue
    working_dir = path.module
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "rm \"exitstatus.${self.triggers.random_uuid}\""
    on_failure = continue
    working_dir = path.module
  }
}

data "external" "stdout" {
  depends_on = [null_resource.publish_layer]
  program    = ["sh", "${local.module_path}/bin/read.sh", "${local.module_path}/stdout.${null_resource.create_layer.id}"]
}

data "external" "stderr" {
  depends_on = [null_resource.publish_layer]
  program    = ["sh", "${local.module_path}/bin/read.sh", "${local.module_path}/stderr.${null_resource.create_layer.id}"]
}

data "external" "exitstatus" {
  depends_on = [null_resource.publish_layer]
  program    = ["sh", "${local.module_path}/bin/read.sh", "${local.module_path}/exitstatus.${null_resource.create_layer.id}"]
}

# could probably make this run on updates to the resulting
# layer zip but one and done is fine for now.
resource "null_resource" "contents" {
  depends_on = [
    null_resource.docker_image_validate,
    null_resource.create_layer,
    null_resource.publish_layer
  ]

  triggers = {
    stdout     = data.external.stdout.result["content"]
    stderr     = data.external.stderr.result["content"]
    exitstatus = data.external.exitstatus.result["content"]
  }

  lifecycle {
    ignore_changes = [triggers]
  }
}

# destroy the layer when terraform destroy is run
resource "null_resource" "layer_cleanup" {

  triggers = {
    layer_arn = chomp(null_resource.contents.triggers["stdout"])
  }

  depends_on = [
    null_resource.contents
  ]

  provisioner "local-exec" {
    when        = destroy
    command     = "bin/delete-layer.sh"
    working_dir = path.module
    environment = {
      LAYER_ARN = self.triggers.layer_arn
    }
  }
}

# destroy the docker image when terraform destroy is run
resource "null_resource" "docker_image_cleanup" {

  triggers = {
    docker_image_name = local.docker_image_name
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker rmi $(docker images '${self.triggers.docker_image_name}' -q) || echo 'image '${self.triggers.docker_image_name}' does not exist'"
  }
}
