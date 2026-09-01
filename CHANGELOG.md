# Changelog

## [1.0.1](https://github.com/spark-match/spark-match-02-infrastructure/compare/v1.0.0...v1.0.1) (2026-09-01)


### Documentation

* actualizar los punteros a repos tras el renumerado ([#233](https://github.com/spark-match/spark-match-02-infrastructure/issues/233)) ([87fcfc0](https://github.com/spark-match/spark-match-02-infrastructure/commit/87fcfc0824aa8fb739d7def0ede2fcc7677d718d))
* **readme:** reflejar los 17 módulos reales y el estado de la cuenta ([#227](https://github.com/spark-match/spark-match-02-infrastructure/issues/227)) ([9bd6c73](https://github.com/spark-match/spark-match-02-infrastructure/commit/9bd6c73f7b6f5e6ee2699ce350952df6a682e9a6))


### CI/CD

* corregir el doble scope en los commits de Dependabot ([#231](https://github.com/spark-match/spark-match-02-infrastructure/issues/231)) ([7ce1917](https://github.com/spark-match/spark-match-02-infrastructure/commit/7ce1917beb52dfb4e6cf186973fa997409b75742))

## [1.0.0](https://github.com/spark-match/spark-match-02-infrastructure/compare/v0.1.0...v1.0.0) (2026-08-04)


### ⚠ BREAKING CHANGES

* **deps:** upgrade hashicorp/aws provider from 5.x to 6.x ([#58](https://github.com/spark-match/spark-match-02-infrastructure/issues/58))

### Features

* **ci:** add terraform-apply.yml workflow ([#4](https://github.com/spark-match/spark-match-02-infrastructure/issues/4)) ([eebca8d](https://github.com/spark-match/spark-match-02-infrastructure/commit/eebca8d926bf1f6c03e6b463a96f2dce938258d9))
* **ci:** quality gates - tflint hook, checkov scan, dependabot, VPC flow logs ([#16](https://github.com/spark-match/spark-match-02-infrastructure/issues/16)) ([a735b40](https://github.com/spark-match/spark-match-02-infrastructure/commit/a735b40a43595c112404d933fc5ffad98144b13d))
* **live/dev:** instantiate networking module + fix data.aws_region bug ([#27](https://github.com/spark-match/spark-match-02-infrastructure/issues/27)) ([2ba53cb](https://github.com/spark-match/spark-match-02-infrastructure/commit/2ba53cba82e94d6feb67e6a73ac3b7f079cb06cf))
* multi-environment support with N-env aware terraform pipelines ([#8](https://github.com/spark-match/spark-match-02-infrastructure/issues/8)) ([98b20d6](https://github.com/spark-match/spark-match-02-infrastructure/commit/98b20d64b668a5ed8f967b27d038727b79748be0))
* **notifications:** new module to manage SNS topic + budget + email subscriptions as IaC ([#28](https://github.com/spark-match/spark-match-02-infrastructure/issues/28)) ([3ea5bc8](https://github.com/spark-match/spark-match-02-infrastructure/commit/3ea5bc88e5c2163d91a73f9e1b2ebe552e389696))
* s3-example POC + cleanup networking references ([#1](https://github.com/spark-match/spark-match-02-infrastructure/issues/1)) ([0f2f8eb](https://github.com/spark-match/spark-match-02-infrastructure/commit/0f2f8ebdfad19b8d138fffb822a86d2b7ff90d07))
* **security:** hardening - KMS key policy, default SG lock, policies reorg, trust policy decision ([#15](https://github.com/spark-match/spark-match-02-infrastructure/issues/15)) ([ce4928c](https://github.com/spark-match/spark-match-02-infrastructure/commit/ce4928cd637b317bd326bc670239300f1e3532a3))
* **terraform:** quality of life - versions.tf, validations, lifecycle, max_session_duration ([#14](https://github.com/spark-match/spark-match-02-infrastructure/issues/14)) ([62bd7a7](https://github.com/spark-match/spark-match-02-infrastructure/commit/62bd7a709940495d6853d7a2344588b1e8f922ed))


### Bug Fixes

* **codeowners:** cover /modules/notifications and remaining /docs files in 02-infra ([#48](https://github.com/spark-match/spark-match-02-infrastructure/issues/48)) ([d1d2996](https://github.com/spark-match/spark-match-02-infrastructure/commit/d1d29965e61ef0e672757a4b529e3f99489fcda3))
* **gitignore:** agregar Python, AWS, Node a las reglas de Terraform ([52f7754](https://github.com/spark-match/spark-match-02-infrastructure/commit/52f775445b1d9aa09f60e2b2a9edcebcc719b4e4))
* **governance:** CODE OWNERS devops, sin product-owners como catch-all ([8bf794d](https://github.com/spark-match/spark-match-02-infrastructure/commit/8bf794d086ec2924c5938cc4a4c075289985db30))
* **governance:** CODEOWNERS simplificado a solo devops ([afd953c](https://github.com/spark-match/spark-match-02-infrastructure/commit/afd953c310b960408ad54feb4f9a225018b50433))
* **governance:** CODEOWNERS simplificado a solo devops ([f99e268](https://github.com/spark-match/spark-match-02-infrastructure/commit/f99e268c9f73f6cd4ef665ccd051893cd08a5402))
* **governance:** CODEOWNERS simplificado a solo devops ([d8e0527](https://github.com/spark-match/spark-match-02-infrastructure/commit/d8e05274be2d457741a58fca18394e07b1aa5b5d))
* **iam:** isolate policies per environment via templatefile() ([#9](https://github.com/spark-match/spark-match-02-infrastructure/issues/9)) ([7daef11](https://github.com/spark-match/spark-match-02-infrastructure/commit/7daef11a0557bda5b9f363b038b3d63002d0e3ea))
* **live/prod:** terraform fmt alignment ([#36](https://github.com/spark-match/spark-match-02-infrastructure/issues/36)) ([f5bbef6](https://github.com/spark-match/spark-match-02-infrastructure/commit/f5bbef67aca0383653979ec5f0027ba664a9c0a2))
* **networking,scripts:** Fase A items A5 (NAT count) and A7 (scripts default) ([#12](https://github.com/spark-match/spark-match-02-infrastructure/issues/12)) ([59271f4](https://github.com/spark-match/spark-match-02-infrastructure/commit/59271f4e03d3e80dea110962ce16122eb399e128))
* **notifications:** encrypt SNS topic with KMS CMK (resolves GHAS CKV_AWS_55) ([#29](https://github.com/spark-match/spark-match-02-infrastructure/issues/29)) ([30c289e](https://github.com/spark-match/spark-match-02-infrastructure/commit/30c289e15ac24bbe63c68b263b4e938687c7d25e))
* **security:** add explicit egress = [] to 3 SGs (lambda, rds, endpoints) ([#26](https://github.com/spark-match/spark-match-02-infrastructure/issues/26)) ([07a72fa](https://github.com/spark-match/spark-match-02-infrastructure/commit/07a72fa052b259394863cf0709145b2c7c894cf1))


### Documentation

* cleanup debug notes and update IAM role ARNs to -prod suffix ([#38](https://github.com/spark-match/spark-match-02-infrastructure/issues/38)) ([6cc9bb1](https://github.com/spark-match/spark-match-02-infrastructure/commit/6cc9bb1c42234841913692913ed249b2e4547a57))
* cleanup pgvector references ([#39](https://github.com/spark-match/spark-match-02-infrastructure/issues/39)) ([af9ebad](https://github.com/spark-match/spark-match-02-infrastructure/commit/af9ebad7dd33062ea9058adcd0fde0d4f919b227))
* **governance:** document bypasses of PRs [#8](https://github.com/spark-match/spark-match-02-infrastructure/issues/8) and [#9](https://github.com/spark-match/spark-match-02-infrastructure/issues/9) ([#10](https://github.com/spark-match/spark-match-02-infrastructure/issues/10)) ([8479ee9](https://github.com/spark-match/spark-match-02-infrastructure/commit/8479ee9bf8e2125b2edeb963d965755a0efd4440))
* **infra:** add tfstate recovery runbook + AWS Budgets section ([#23](https://github.com/spark-match/spark-match-02-infrastructure/issues/23)) ([5567323](https://github.com/spark-match/spark-match-02-infrastructure/commit/5567323944af17454653f541e6d8a2dad770c447))
* **infra:** documentar decisiones C1 (SSE-KMS) y C16 (endpoints) ([#25](https://github.com/spark-match/spark-match-02-infrastructure/issues/25)) ([85506b6](https://github.com/spark-match/spark-match-02-infrastructure/commit/85506b6103080e7f9ec5986739e71077cf824cfc))


### CI/CD

* **deps:** bump Actions to latest stable (checkov workflow) ([#24](https://github.com/spark-match/spark-match-02-infrastructure/issues/24)) ([17847fb](https://github.com/spark-match/spark-match-02-infrastructure/commit/17847fb56b11bab8dc18960d8a2a6554dbd3e20a))


### Tests

* split plan/apply roles ([#3](https://github.com/spark-match/spark-match-02-infrastructure/issues/3)) ([4be6052](https://github.com/spark-match/spark-match-02-infrastructure/commit/4be605240b2c0bc738574f932253fc0519e922ea))
* verify OIDC works ([#2](https://github.com/spark-match/spark-match-02-infrastructure/issues/2)) ([8033d14](https://github.com/spark-match/spark-match-02-infrastructure/commit/8033d144e11067886a31a3ca7a2d0ef51e6c86c2))


### Miscellaneous

* **deps:** upgrade hashicorp/aws provider from 5.x to 6.x ([#58](https://github.com/spark-match/spark-match-02-infrastructure/issues/58)) ([3ebca78](https://github.com/spark-match/spark-match-02-infrastructure/commit/3ebca7823e78cc47f29f08d65ad56592e7ac3d7d))
