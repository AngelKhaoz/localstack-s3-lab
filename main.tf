# 1. El bucket.
resource "aws_s3_bucket" "seguro" {
  bucket = "actividad3-seguro-local"

  tags = {
    Proyecto = "actividad3-iac"
    Entorno  = "local"
  }
}

# 2. Cifrado en reposo SSE-S3 (AES-256), aplicado por defecto a cada objeto.
resource "aws_s3_bucket_server_side_encryption_configuration" "cifrado" {
  bucket = aws_s3_bucket.seguro.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 3. Bloqueo de acceso publico: los cuatro controles activados.
resource "aws_s3_bucket_public_access_block" "bloqueo" {
  bucket = aws_s3_bucket.seguro.id

  block_public_acls       = true # Rechaza ACLs publicas nuevas.
  block_public_policy     = true # Rechaza politicas de bucket publicas.
  ignore_public_acls      = true # Ignora las ACLs publicas que ya existan.
  restrict_public_buckets = true # Limita el acceso a principales autorizados.
}

output "bucket" {
  description = "Nombre del bucket creado."
  value       = aws_s3_bucket.seguro.id
}
