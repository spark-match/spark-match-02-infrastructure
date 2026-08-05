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
# Limite duro de AWS para el documento de una managed policy.
MAX_MANAGED_POLICY_BYTES = 6144

POLICIES = {
    "spark-match-tf-apply-refresh": (
        "Describe/list que el refresh de terraform necesita en {env}, mas el "
        "arreglo de los patrones de SSM y Logs"
    ),
    "spark-match-tf-apply-compute": (
        "ECS/ELBv2/ECR + PassRole a ecs-tasks + service-linked roles para los "
        "modulos ecr y agent-service en {env}"
    ),
}


def render(stem: str, env: str) -> dict:
    """Lee el JSON e interpola ${environment}, igual que templatefile() de Terraform."""
    raw = (POLICIES_DIR / f"{stem}.json").read_text(encoding="utf-8")
    return json.loads(raw.replace("${environment}", env))


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
    role = f"spark-match-terraform-apply-{env}"
    rendered = {stem: render(stem, env) for stem in POLICIES}

    print(f"Rol destino: {role}\n")
    for stem, doc in rendered.items():
        body = json.dumps(doc, separators=(",", ":"))
        print(f"--- {stem}-{env}: {len(doc['Statement'])} statements, {len(body)} bytes ---")
        for statement in doc["Statement"]:
            actions = statement["Action"]
            actions = [actions] if isinstance(actions, str) else actions
            print(f"  {statement['Sid']:35s} {len(actions):3d} acciones")
    print()

    if not args.apply:
        print("DRY-RUN: no se aplico nada. Volve a correr con --apply.")
        return 0

    iam = boto3.Session(profile_name=args.profile).client("iam")
    for stem, doc in rendered.items():
        print(f"{stem}-{env}:")
        upsert(iam, f"{stem}-{env}", doc, role, POLICIES[stem].format(env=env))

    print("\nListo. Verifica con:")
    print(f"  aws iam list-attached-role-policies --role-name {role} --profile {args.profile}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
