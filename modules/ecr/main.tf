###############################################################################
# Module: ecr
#
# Repositorio ECR donde spark-match-07-deep-agent publica la imagen del agente
# (ARM64 / Graviton, ver el Dockerfile de ese repo: ambas etapas usan
# `--platform=linux/arm64`). El consumidor es modules/agent-service, que corre
# la imagen en ECS Fargate.
#
# El nombre resultante (`{project_name}-{repository_suffix}-{environment}`,
# por defecto `spark-match-agent-advisor-{env}`) NO es cosmetico: tiene que
# caer dentro del allowlist IAM
# `arn:aws:ecr:us-east-1:681526276858:repository/spark-match-agent-*-{env}`
# de modules/oidc-github/policies/{env}/spark-match-bedrock-agentcore-deploy.json.
# La validation de var.repository_suffix protege esa invariante.
###############################################################################

locals {
  common_tags = merge(
    var.tags,
    {
      Module      = "ecr"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "spark-match/spark-match-02-infrastructure"
    }
  )

  repository_name = "${var.project_name}-${var.repository_suffix}-${var.environment}"
}

resource "aws_ecr_repository" "this" {
  name                 = local.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # `latest` tiene que poder reescribirse; el resto no.
  #
  # El pipeline del agente publica `latest,<sha>` en cada build. Con el
  # repositorio en IMMUTABLE puro, el primer push crea `latest` y TODOS los
  # siguientes mueren con "The image tag 'latest' already exists ... and
  # cannot be overwritten because the tag is immutable" -- despues de haber
  # subido las capas, asi que ademas deja imagenes sin tag acumulandose.
  #
  # Bajar todo el repositorio a MUTABLE seria tirar la propiedad que
  # realmente importa: que un `<sha>` ya desplegado no pueda cambiar de
  # digest bajo los pies. Esa es la que protege el rollback y la auditoria.
  # `latest` no la necesita porque nadie despliega por ese tag: el pipeline
  # rota ECS por digest, y el unico consumidor de `latest` es el
  # container_image de bootstrap de la task definition, que solo se lee en
  # el primer apply de un entorno nuevo.
  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = endswith(var.image_tag_mutability, "_WITH_EXCLUSION") ? var.mutable_tag_filters : []

    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  # Con kms_key_arn = null se cae al default de ECR (AES256 con key
  # administrada por AWS, sin costo). El bloque se emite igual en ambos casos
  # para que el `encryption_type` quede explicito en el state y un cambio
  # futuro sea visible en el plan.
  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(local.common_tags, {
    Name = local.repository_name
  })
}

# Lifecycle policy: conservar las ultimas N imagenes con tag y expirar las
# untagged a los 7 dias. Las untagged aparecen cuando un push reescribe un
# manifest (multi-arch) o cuando un build falla a medias -- no sirven para
# rollback y solo acumulan costo de storage.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expirar imagenes untagged despues de 7 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Conservar solo las ultimas ${var.max_image_count} imagenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
