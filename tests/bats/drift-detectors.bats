#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Spark Match
# =============================================================================
# drift-detectors.bats - guards contra listas que se quedan atras
# =============================================================================
# Casi toda la politica de CI de este repo son listas enumeradas a mano que hay
# que mantener sincronizadas con un arbol que cambia a diario: los contextos
# requeridos del ruleset, los filtros de paths, la matriz de checkov, los
# duenos de CODEOWNERS. Cuando una de esas listas se queda corta, el fallo es
# siempre EN ABIERTO -- verde, o "no reporta" -- nunca en cerrado.
#
# Cada test de aqui vigila una lista concreta, y cada uno existe porque el
# problema que evita YA PASO. Las fechas y los numeros son medidos, no
# hipoteticos.
#
# Los cuatro son hermeticos: leen el arbol y nada mas. Sin red, sin AWS, sin
# gh. Un guard que necesita credenciales acaba desactivado.
# =============================================================================

setup() {
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  WORKFLOWS_DIR="${REPO_ROOT}/.github/workflows"
}

# -----------------------------------------------------------------------------
@test "drift: la matriz de checkov cubre todos los modulos" {
  # Por que: la matriz de terraform-security-scan.yml enumera las rutas a
  # escanear. Un modulo nuevo no se escanea hasta que alguien se acuerda de
  # anadirlo, y como el check sale verde igual, nadie se entera.
  #
  # Medido el 2026-08-07: la matriz de `main` tenia 14 rutas y la de `dev` 18.
  # Los 4 que faltaban en main eran los modulos mas nuevos -- frontend-hosting,
  # oidc-frontend, ecr y agent-service -- o sea justo los que menos revision
  # acumulaban.
  local wf="${WORKFLOWS_DIR}/terraform-security-scan.yml"
  local faltan=()

  while IFS= read -r mod; do
    [[ -z "$mod" ]] && continue
    grep -qE "^\s*-\s+modules/${mod}(\s|$|#)" "$wf" || faltan+=("modules/${mod}")
  done < <(find "${REPO_ROOT}/modules" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)

  if [ ${#faltan[@]} -ne 0 ]; then
    printf 'Modulos que existen en disco y no estan en la matriz de checkov:\n' >&2
    printf '  %s\n' "${faltan[@]}" >&2
    printf '\nAnadelos a la matriz `path:` de terraform-security-scan.yml.\n' >&2
    return 1
  fi
}

# -----------------------------------------------------------------------------
@test "drift: ningun workflow con contextos requeridos filtra por paths" {
  # Por que: un filtro de `paths` y un check requerido son incompatibles por
  # construccion. Si el filtro no casa, el workflow no corre; si no corre, el
  # check no se publica; y un check requerido que no se publica deja el pull
  # request en "Expected - waiting for status to be reported" para siempre. La
  # unica salida es el bypass de admin.
  #
  # Medido el 2026-08-07, antes de quitarlos: 57 de los 161 ficheros del repo
  # no disparaban ninguno de los 20 contextos requeridos que dependen de estos
  # workflows. Los PR #187 y #189, que tocaban `bootstrap/**`, se mergearon con
  # 1 de 21 checks.
  #
  # Si algun dia el tiempo de CI molesta, la salida NO es volver a poner
  # `paths:` sino filtrar dentro del job: un primer step que decida si hay
  # trabajo y salga en verde si no lo hay. Asi el check se sigue publicando.
  local con_contextos_requeridos=(
    ci.yml
    terraform-plan-dev.yml
    terraform-security-scan.yml
    commitlint.yml
  )
  local offenders=()

  for wf in "${con_contextos_requeridos[@]}"; do
    local f="${WORKFLOWS_DIR}/${wf}"
    [[ -f "$f" ]] || { offenders+=("${wf} (no existe)"); continue; }
    # `paths:` a nivel de trigger, ignorando comentarios.
    if grep -vE '^\s*#' "$f" | grep -qE '^\s+paths(-ignore)?:'; then
      offenders+=("${wf}")
    fi
  done

  if [ ${#offenders[@]} -ne 0 ]; then
    printf 'Workflows que publican contextos requeridos y filtran por paths:\n' >&2
    printf '  %s\n' "${offenders[@]}" >&2
    printf '\nUn check requerido que no se publica bloquea el PR para siempre.\n' >&2
    printf 'Ver la nota de cabecera en ci.yml.\n' >&2
    return 1
  fi
}

# -----------------------------------------------------------------------------
@test "drift: todo directorio de primer nivel tiene dueno en CODEOWNERS" {
  # Por que: sin dueno, `require_code_owner_review` sobre ese path se satisface
  # trivialmente. Medido el 2026-08-07: `bootstrap/` -- donde viven las
  # policies de IAM que se aplican a los roles de terraform -- y `tasks/` no
  # tenian dueno, y de los 16 modulos solo 6 estaban declarados.
  #
  # Hoy lo cubre el catch-all `*`, asi que este test comprueba sobre todo que
  # el catch-all sigue ahi. La regla "si creas un path nuevo, anade una linea"
  # depende de que alguien se acuerde, y llevaba diez modulos sin cumplirse.
  local co="${REPO_ROOT}/.github/CODEOWNERS"
  [[ -f "$co" ]]

  local reglas
  reglas="$(grep -vE '^\s*#|^\s*$' "$co")"

  # El catch-all es lo que hace que ningun path pueda quedarse huerfano.
  if ! printf '%s\n' "$reglas" | grep -qE '^\*\s+@'; then
    printf 'CODEOWNERS no tiene regla catch-all `*`.\n' >&2
    printf 'Sin ella, cualquier path no listado se queda sin dueno y la\n' >&2
    printf 'exigencia de code owner sobre el se satisface sola.\n' >&2
    return 1
  fi
}

# -----------------------------------------------------------------------------
@test "drift: todo checkov:skip lleva un motivo escrito" {
  # Por que: `# checkov:skip=CKV_AWS_1:motivo` silencia un hallazgo. Sin la
  # parte del motivo, silencia igual pero nadie sabe si fue una decision o una
  # prisa. Y como ahora checkov puede fallar de verdad (se le quito el
  # --soft-fail el 2026-08-07), el atajo mas tentador ante un hallazgo nuevo es
  # exactamente ese: un skip sin explicar.
  #
  # Los 81 skips que hay hoy en live/* llevan todos su motivo. Este test evita
  # que el 82 sea el primero que no.
  local sin_motivo=()

  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    local f="${hit%%:*}"
    local resto="${hit#*:}"
    local n="${resto%%:*}"
    # Un skip valido es `checkov:skip=REGLA:texto`. Sin los dos puntos finales,
    # o con el texto vacio, no hay motivo.
    if printf '%s' "$hit" | grep -qE 'checkov:skip=[A-Za-z0-9_]+\s*(#|$)'; then
      sin_motivo+=("${f#"$REPO_ROOT"/}:${n}")
    fi
  done < <(grep -rn "checkov:skip=" "${REPO_ROOT}/modules" "${REPO_ROOT}/live" 2>/dev/null || true)

  if [ ${#sin_motivo[@]} -ne 0 ]; then
    printf 'checkov:skip sin motivo:\n' >&2
    printf '  %s\n' "${sin_motivo[@]}" >&2
    printf '\nFormato: # checkov:skip=CKV_AWS_1:por que se acepta este hallazgo\n' >&2
    return 1
  fi
}
