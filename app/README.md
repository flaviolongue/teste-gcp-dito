# app/

Aplicação de exemplo do desafio. É um serviço nginx que serve uma página
estática e expõe `/healthz` para os probes do Kubernetes.

Numa aplicação real, este diretório conteria o código-fonte da API. O que
importa para o desafio é a esteira: alterações aqui disparam o workflow de
build + push da imagem + atualização do manifesto (ver `.github/workflows/app.yml`).

## Como a aplicação recebe configuração

A aplicação lê configuração por variáveis de ambiente, separadas em dois grupos:

- **Não sensíveis** — vêm de um `ConfigMap` (ex.: `APP_ENV`, `LOG_LEVEL`,
  `DB_HOST`, `DB_NAME`). Ver `manifests/base/configmap.yaml`.
- **Sensíveis** — vêm de um `Secret` do Kubernetes, que por sua vez é
  populado a partir do GCP Secret Manager pelo External Secrets Operator
  (ex.: `DB_PASSWORD`, `APP_API_KEY`). Ver `manifests/base/externalsecret.yaml`.

## Build local

```bash
docker build -t dito-internal-api:local ./app
docker run --rm -p 8080:8080 dito-internal-api:local
curl localhost:8080/healthz   # -> ok
```
