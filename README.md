# Bucket S3 seguro con Terraform y LocalStack

Laboratorio de Infraestructura como Código (IaC). Se construye un bucket S3
simulado con Terraform, se declaran su cifrado en reposo y sus controles de
bloqueo de acceso público, y se comprueba qué queda **realmente** configurado y
qué se aplica de verdad al atender peticiones.

Todo corre en local. **No se usa ni se requiere una cuenta de AWS.**

---

## Requisitos

| Herramienta | Versión usada | Para qué |
|---|---|---|
| Docker Engine / Desktop | 27.5.1 | Ejecutar contenedores |
| Docker Compose | v2.32.4 | Levantar LocalStack |
| Terraform | v1.17.1 | Definir y aplicar la infraestructura |
| Provider AWS | v5.100.0 | Recursos S3 (lo descarga `terraform init`) |
| AWS CLI | v2.40.0 | Consultar el S3 simulado |
| LocalStack | 2026.10.6 (pro) | Emular S3 en `localhost:4566` |

Hace falta además una cuenta gratuita de LocalStack (plan **Hobby — Free**) para
obtener el token de autenticación.

---

## Estructura

```
localstack-s3-lab/
├── compose.yaml            LocalStack: puerto 4566 solo en localhost, S3, token por entorno
├── providers.tf            Provider AWS apuntado al endpoint local
├── main.tf                 Bucket + cifrado AES256 + bloqueo público (3 recursos)
├── .env.example            Plantilla del token
├── .env                    Token real — NO se versiona
├── .gitignore              Excluye secretos, estado y datos locales
└── reparar-dashboard.ps1   Script auxiliar de recuperación
```

---

## Cómo reproducirlo

**1. Configurar el token**

```powershell
Copy-Item .env.example .env
notepad .env   # pegar el token de LocalStack
```

**2. Levantar LocalStack**

```powershell
docker compose up -d
docker compose ps                                   # debe decir (healthy)
curl.exe http://localhost:4566/_localstack/health   # "s3": "available"
```

**3. Aplicar la infraestructura**

```powershell
terraform init
terraform validate
terraform plan      # Plan: 3 to add, 0 to change, 0 to destroy
terraform apply
```

**4. Verificar con AWS CLI**

Las credenciales son ficticias y solo viven en la sesión de la terminal:

```powershell
$env:AWS_ACCESS_KEY_ID     = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION    = "us-east-1"
```

Cada comando lleva `--endpoint-url` **explícito**: es lo que garantiza que
ninguna petición salga hacia AWS real.

```powershell
aws --endpoint-url http://localhost:4566 s3api list-buckets
aws --endpoint-url http://localhost:4566 s3api get-bucket-encryption   --bucket actividad3-seguro-local
aws --endpoint-url http://localhost:4566 s3api get-public-access-block --bucket actividad3-seguro-local
```

**5. Probar el comportamiento real**

```powershell
"Archivo de prueba - laboratorio S3 seguro" | Set-Content prueba.txt
aws --endpoint-url http://localhost:4566 s3 cp prueba.txt s3://actividad3-seguro-local/
aws --endpoint-url http://localhost:4566 s3 ls s3://actividad3-seguro-local/

# Acceso anónimo, sin firmar la solicitud
aws --endpoint-url http://localhost:4566 s3api get-object --bucket actividad3-seguro-local --key prueba.txt descarga-anonima.txt --no-sign-request
curl.exe -i http://localhost:4566/actividad3-seguro-local/prueba.txt

# Estado de la política del bucket
aws --endpoint-url http://localhost:4566 s3api get-bucket-policy --bucket actividad3-seguro-local
```

---

## Resultados observados

| Comprobación | Resultado |
|---|---|
| `terraform plan` | `3 to add, 0 to change, 0 to destroy` |
| `terraform apply` | `3 added` |
| `get-bucket-encryption` | `"SSEAlgorithm": "AES256"` |
| `get-public-access-block` | Los cuatro controles en `true` |
| Objeto subido | `prueba.txt`, 43 bytes |
| Descarga anónima (`--no-sign-request`) | **Permitida** |
| `curl` sin credenciales | **`HTTP/1.1 200 OK`** con el contenido del archivo |
| Encabezado de la respuesta | `x-amz-server-side-encryption: AES256` |
| `get-bucket-policy` | `NoSuchBucketPolicy` |

### Sobre el `NoSuchBucketPolicy`

No indica exposición pública. Significa únicamente que **nunca se adjuntó una
política de bucket**, que es justamente lo declarado: el laboratorio configura
cifrado y bloqueo de acceso público, no una política. Un bucket sin política no
es un bucket abierto; en AWS real, la ausencia de política implica denegación
por defecto.

### Sobre la descarga anónima

LocalStack entregó el archivo a una petición sin firmar. En AWS real la misma
petición devolvería `403 AccessDenied`: S3 deniega por defecto todo lo que no
esté explícitamente autorizado.

La diferencia no está en la configuración —que se guardó correctamente, como
confirman las consultas— sino en que **LocalStack no aplica autorización IAM de
forma predeterminada**. Reproduce con fidelidad el *almacenamiento* del estado,
no su *cumplimiento*. Conforme al criterio de seguridad de la actividad, esto se
trata como una limitación del simulador y no como una validación de que el
bucket sea seguro o inseguro.

---

## Conclusión

El laboratorio distingue tres cosas que suelen confundirse:

**Infraestructura declarada.** Lo que dice el código. En `main.tf` hay un bucket
con cifrado AES256 y los cuatro controles de bloqueo público en `true`. Es una
intención expresada, nada más.

**Configuración consultada.** Lo que el servicio reporta al preguntarle.
`get-bucket-encryption` y `get-public-access-block` devolvieron exactamente lo
declarado. Esto confirma que el estado se guardó, no que se esté respetando.

**Seguridad efectivamente aplicada.** Lo que ocurre cuando alguien toca la
puerta. Aquí las dos protecciones se separaron: el cifrado **sí** operó —el
objeto volvió con `x-amz-server-side-encryption: AES256`—, mientras que el
bloqueo de acceso público **no** impidió nada: una petición anónima obtuvo
`200 OK` y el contenido en claro.

La lección es que las dos primeras capas pueden coincidir perfectamente y aun
así no decir nada sobre la tercera. Un informe basado solo en el código o solo
en consultas de configuración habría concluido que el bucket estaba protegido.
Solo intentar el acceso reveló la diferencia. Verificar seguridad exige probar
comportamiento, no leer declaraciones; y hacerlo en un entorno que no replica el
motor de autorización del servicio real obliga a interpretar los resultados con
cuidado en lugar de darlos por buenos.

---

## Notas de seguridad

- El puerto `4566` se publica solo en `127.0.0.1`: no queda expuesto a la red local.
- El token de LocalStack se inyecta por variable de entorno desde `.env`, que está en `.gitignore`. No aparece en ningún archivo versionado.
- Las credenciales AWS son ficticias (`test` / `test`) y el endpoint es local: ninguna operación puede alcanzar una cuenta real.
- No se versionan `*.tfstate` ni `.terraform/`: el estado puede contener datos sensibles.

## Fuentes

- [LocalStack · Precios](https://www.localstack.cloud/pricing)
- [LocalStack · Documentación](https://docs.localstack.cloud/)
- [Docker · Documentación](https://docs.docker.com/)
- [Terraform · Instalación](https://developer.hashicorp.com/terraform/install)
- [AWS CLI · Documentación](https://docs.aws.amazon.com/cli/)
