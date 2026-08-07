#!/usr/bin/env python3
"""Aplica las managed policies de bootstrap sobre spark-match-terraform-apply-{env}.

Estas policies NO las gestiona Terraform a proposito. Ver bootstrap/README.md.

El script es idempotente: si la policy ya existe, publica una version nueva y la
deja como default (borrando antes las no-default, porque IAM permite 5 como
maximo). El attach tambien es idempotente.

Uso:
    python bootstrap/apply-bootstrap-policies.py dev            # dry-run
    python bootstrap/apply-bootstrap-policies.py dev --apply
    python bootstrap/apply-bootstrap-policies.py prod --apply

Requiere el perfil AWS `spark-match-admin` (o AWS_PROFILE apuntando a un
principal con permisos de IAM sobre la cuenta 681526276858).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import boto3
except ImportError:  # pragma: no cover - guia al usuario, no es logica de negocio
    sys.exit("Falta boto3. Instalalo con: pip install boto3")

ACCOUNT = "681526276858"
POLICIES_DIR = Path(__file__).parent / "policies"
TRUST_DIR = Path(__file__).parent / "trust"
BACKUP_DIR = Path(__file__).parent.parent / "backups" / "trust"
SUB_CLAIM = "token.actions.githubusercontent.com:sub"
# Limite duro de AWS para el documento de una managed policy.
MAX_MANAGED_POLICY_BYTES = 6144

# stem -> (rol destino, descripcion). El rol se formatea con {env}.
POLICIES = {
    "spark-match-tf-apply-refresh": (
        "spark-match-terraform-apply-{env}",
        "Describe/list que el refresh de terraform necesita en {env}, mas el "
        "arreglo de los patrones de SSM y Logs",
    ),
    "spark-match-tf-apply-compute": (
        "spark-match-terraform-apply-{env}",
        "ECS/ELBv2/ECR + PassRole a ecs-tasks + service-linked roles para los "
        "modulos ecr y agent-service en {env}",
    ),
    "spark-match-tf-apply-create": (
        "spark-match-terraform-apply-{env}",
        "Creacion inicial de recursos en {env}: buckets de aplicacion, "
        "distribuciones CloudFront, RDS, secrets, tablas DynamoDB, bus de "
        "EventBridge, NAT/EIP/flow logs y el data source del OIDC provider",
    ),
    "spark-match-tf-plan-read": (
        "spark-match-terraform-plan-{env}",
        "Lectura de todo y escritura de nada, para que terraform plan pueda "
        "refrescar el state en {env}",
    ),
}


def render(stem: str, env: str) -> dict:
    """Lee el JSON e interpola ${environment}, igual que templatefile() de Terraform."""
    raw = (POLICIES_DIR / f"{stem}.json").read_text(encoding="utf-8")
    return json.loads(raw.replace("${environment}", env))


def trust_documents(env: str) -> dict[str, dict]:
    """Devuelve {nombre-de-rol: documento} para las trust policies de este env.

    Una por rol y sin plantillas a proposito. Los cuatro roles NO comparten
    forma: `plan-dev` necesita ademas `:pull_request`, porque su caller pasa el
    environment vacio en pull requests, y los de prod no lo necesitan en
    absoluto. Un fichero por rol hace que esa diferencia se lea, en vez de
    esconderse en un condicional. Ver bootstrap/trust/README.md.
    """
    documents = {}
    for path in sorted(TRUST_DIR.glob(f"*-{env}.json")):
        documents[path.stem] = json.loads(path.read_text(encoding="utf-8"))
    return documents


def _subs(document: dict) -> list[str]:
    """Los `sub` de una trust policy, siempre como lista.

    AWS devuelve el claim como string cuando el valor es uno solo y como lista
    cuando son varios. Sin normalizar, un `set(...)` sobre el string itera
    caracteres, y `len(...)` cuenta caracteres.
    """
    value = document["Statement"][0]["Condition"]["StringLike"][SUB_CLAIM]
    return [value] if isinstance(value, str) else list(value)


def _canonical(document: dict) -> str:
    """Forma comparable de una trust policy.

    Misma asimetria string/lista que arriba: sin aplanarla, el documento que
    mandamos y el que AWS devuelve salen distintos aunque digan lo mismo.
    """
    document = json.loads(json.dumps(document))
    for statement in document.get("Statement", []):
        condition = statement.get("Condition", {}).get("StringLike", {})
        if isinstance(condition.get(SUB_CLAIM), str):
            condition[SUB_CLAIM] = [condition[SUB_CLAIM]]
    return json.dumps(document, sort_keys=True)


def _write_backup(current: dict, backup_dir: Path, role: str) -> Path:
    """Guarda la policy vigente SIN pisar un respaldo anterior.

    El nombre sin sufijo se escribe una sola vez, y es el que de verdad
    querrias recuperar: el estado anterior a la primera ejecucion. Las
    siguientes llevan sufijo incremental.

    Pisarlo fue un fallo real. El 2026-08-07 el script corrio dos veces sobre
    los mismos roles y el segundo respaldo -- ya con la policy nueva -- tapo al
    original. El fichero seguia ahi y el script seguia imprimiendo "respaldo en
    ...", asi que la marcha atras parecia cubierta cuando ya no lo estaba. Es
    la misma forma que el resto de fallos en abierto de este proyecto: la senal
    de que algo esta protegido sobrevive a la proteccion.
    """
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / f"{role}.json"
    serial = 1
    while backup.exists():
        backup = backup_dir / f"{role}.{serial}.json"
        serial += 1
    backup.write_text(json.dumps(current, indent=2), encoding="utf-8")
    return backup


def update_trust(iam, role: str, doc: dict, backup_dir: Path) -> None:
    """Reemplaza la trust policy del rol, guardando antes la actual.

    `update_assume_role_policy` no es un merge: sustituye el documento entero.
    Por eso el respaldo va ANTES y, si falla, no se escribe nada -- mismo
    contrato que el reconciliador de rulesets en 01-devops.

    Si lo vigente ya coincide con lo versionado no se toca nada: ni respaldo ni
    llamada a IAM. Volver a correr el script sobre un rol ya reconciliado es
    entonces un no-op de verdad, y no una escritura que ademas se lleva por
    delante el respaldo util.
    """
    current = iam.get_role(RoleName=role)["Role"]["AssumeRolePolicyDocument"]

    if _canonical(current) == _canonical(doc):
        print("  sin cambios   lo vigente ya es lo versionado")
        return

    backup = _write_backup(current, backup_dir, role)
    before = _subs(current)
    after = _subs(doc)
    print(f"  respaldo en   {backup}")
    print(f"  sub claims    {len(before)} -> {len(after)}")
    for gone in sorted(set(before) - set(after)):
        print(f"    quita  {gone}")
    for added in sorted(set(after) - set(before)):
        print(f"    anade  {added}")

    iam.update_assume_role_policy(
        RoleName=role, PolicyDocument=json.dumps(doc, separators=(",", ":"))
    )
    print(f"  actualizada   {role}")


def upsert(iam, name: str, doc: dict, role: str, description: str) -> None:
    body = json.dumps(doc, separators=(",", ":"))
    if len(body) > MAX_MANAGED_POLICY_BYTES:
        sys.exit(f"{name}: {len(body)} bytes supera el limite de {MAX_MANAGED_POLICY_BYTES}")

    arn = f"arn:aws:iam::{ACCOUNT}:policy/{name}"
    try:
        iam.create_policy(PolicyName=name, PolicyDocument=body, Description=description)
        print(f"  creada        {arn}")
    except iam.exceptions.EntityAlreadyExistsException:
        for version in iam.list_policy_versions(PolicyArn=arn)["Versions"]:
            if not version["IsDefaultVersion"]:
                iam.delete_policy_version(PolicyArn=arn, VersionId=version["VersionId"])
        iam.create_policy_version(PolicyArn=arn, PolicyDocument=body, SetAsDefault=True)
        print(f"  version nueva {arn}")

    iam.attach_role_policy(RoleName=role, PolicyArn=arn)
    print(f"  adjuntada a   {role}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("environment", choices=["dev", "prod"])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Aplica de verdad. Sin este flag solo imprime lo que haria.",
    )
    parser.add_argument("--profile", default="spark-match-admin")
    args = parser.parse_args()

    env = args.environment
    rendered = {stem: render(stem, env) for stem in POLICIES}

    for stem, doc in rendered.items():
        role = POLICIES[stem][0].format(env=env)
        body = json.dumps(doc, separators=(",", ":"))
        print(f"--- {stem}-{env} -> {role}")
        print(f"    {len(doc['Statement'])} statements, {len(body)} bytes")
        for statement in doc["Statement"]:
            actions = statement.get("Action") or statement.get("NotAction")
            actions = [actions] if isinstance(actions, str) else actions
            effect = statement["Effect"]
            print(f"    {statement['Sid']:35s} {effect:6s} {len(actions):3d} acciones")
    print()

    trust = trust_documents(env)
    for role, doc in trust.items():
        print(f"--- trust de {role}")
        for sub in _subs(doc):
            print(f"    {sub}")
    print()

    if not args.apply:
        print("DRY-RUN: no se aplico nada. Volve a correr con --apply.")
        return 0

    iam = boto3.Session(profile_name=args.profile).client("iam")
    roles = set()
    for stem, doc in rendered.items():
        role_template, description = POLICIES[stem]
        role = role_template.format(env=env)
        roles.add(role)
        print(f"{stem}-{env}:")
        upsert(iam, f"{stem}-{env}", doc, role, description.format(env=env))

    # Las trust policies van DESPUES de los permisos. Si algo falla a mitad, el
    # rol se queda con permisos nuevos y confianza vieja, que es inocuo: sigue
    # asumiendose igual. Al reves -- confianza nueva y permisos viejos -- el
    # despliegue arranca y muere a medio apply.
    for role, doc in trust.items():
        print(f"{role} (trust):")
        update_trust(iam, role, doc, BACKUP_DIR)

    print("\nListo. Verifica con:")
    for role in sorted(roles | set(trust)):
        print(f"  aws iam list-attached-role-policies --role-name {role} --profile {args.profile}")
    print("\nY las trust policies con:")
    for role in sorted(trust):
        print(
            f"  aws iam get-role --role-name {role} --profile {args.profile} "
            f"--query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringLike'"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
