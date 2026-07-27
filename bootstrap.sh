#!/usr/bin/env bash
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/ThiagoCarrere/lab/main"
MARCADOR_INICIO='<!-- DIRETRIZES:INICIO (gerenciado automaticamente - nao editar entre os marcadores) -->'
MARCADOR_FIM='<!-- DIRETRIZES:FIM -->'

# 0. Repositorio git
if [ ! -d .git ]; then
  git init -q
fi

mkdir -p .claude/commands .claude/hooks

TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# 1. Diretrizes -> CLAUDE.md (Claude Code le esse arquivo automaticamente ao abrir o projeto)
curl --ssl-no-revoke -fsSL "$REPO_BASE/info.md" -o "$TMPDIR_LOCAL/info.md"

{
  printf '%s\n' "$MARCADOR_INICIO"
  cat "$TMPDIR_LOCAL/info.md"
  printf '\n%s\n' "$MARCADOR_FIM"
} > "$TMPDIR_LOCAL/bloco.md"

if [ -f CLAUDE.md ] && grep -qF "$MARCADOR_INICIO" CLAUDE.md; then
  MARCADOR_INICIO="$MARCADOR_INICIO" MARCADOR_FIM="$MARCADOR_FIM" BLOCO_FILE="$TMPDIR_LOCAL/bloco.md" \
    perl -0777 -i -pe '
      open(my $fh, "<:raw", $ENV{BLOCO_FILE}) or die $!;
      local $/;
      my $bloco = <$fh>;
      close $fh;
      my $ini = quotemeta($ENV{MARCADOR_INICIO});
      my $fim = quotemeta($ENV{MARCADOR_FIM});
      s/$ini.*?$fim/$bloco/s;
    ' CLAUDE.md
elif [ -f CLAUDE.md ]; then
  printf '\n\n' >> CLAUDE.md
  cat "$TMPDIR_LOCAL/bloco.md" >> CLAUDE.md
else
  cp "$TMPDIR_LOCAL/bloco.md" CLAUDE.md
fi

# 2. Permissoes genericas (mescla com o que ja existir, sem sobrescrever)
curl --ssl-no-revoke -fsSL "$REPO_BASE/permissions.json" -o "$TMPDIR_LOCAL/permissions.json"

cat > "$TMPDIR_LOCAL/mesclar-permissoes.ps1" <<'PSEOF'
param(
    [string]$SettingsPath,
    [string]$PermissoesPath
)
$ErrorActionPreference = 'Stop'
$novas = (Get-Content $PermissoesPath -Raw | ConvertFrom-Json).permissions.allow

if (Test-Path $SettingsPath) {
    $json = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $json = [PSCustomObject]@{}
}
if (-not ($json.PSObject.Properties.Name -contains 'permissions')) {
    $json | Add-Member -MemberType NoteProperty -Name 'permissions' -Value ([PSCustomObject]@{})
}
if (-not ($json.permissions.PSObject.Properties.Name -contains 'allow')) {
    $json.permissions | Add-Member -MemberType NoteProperty -Name 'allow' -Value @()
}
$existente = @($json.permissions.allow)
$mesclado = [System.Collections.ArrayList]@($existente)
foreach ($item in $novas) {
    if ($existente -notcontains $item) { [void]$mesclado.Add($item) }
}
$json.permissions.allow = @($mesclado)

$utf8SemBom = New-Object System.Text.UTF8Encoding $false
$caminhoAbsoluto = Join-Path (Get-Location).Path $SettingsPath
[System.IO.File]::WriteAllText($caminhoAbsoluto, ($json | ConvertTo-Json -Depth 10), $utf8SemBom)
PSEOF

powershell -NoProfile -ExecutionPolicy Bypass -File "$TMPDIR_LOCAL/mesclar-permissoes.ps1" -SettingsPath ".claude/settings.local.json" -PermissoesPath "$TMPDIR_LOCAL/permissions.json"

# 3. Hook de resincronizacao automatica
curl --ssl-no-revoke -fsSL "$REPO_BASE/hooks/lembrete-diretrizes.ps1" -o .claude/hooks/lembrete-diretrizes.ps1

# 4. Comandos manuais (fallback para reload sob demanda)
curl --ssl-no-revoke -fsSL "$REPO_BASE/.claude/commands/diretrizes.md" -o .claude/commands/diretrizes.md
curl --ssl-no-revoke -fsSL "$REPO_BASE/.claude/commands/setup.md" -o .claude/commands/setup.md

# 5. Registro do hook
cat > .claude/settings.json <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \".claude\\hooks\\lembrete-diretrizes.ps1\""
          }
        ]
      }
    ]
  }
}
EOF

# 6. task.md
if [ ! -f task.md ]; then
  cat > task.md <<'EOF'
# Tarefas

<!-- Novas tarefas sempre no topo, logo abaixo deste comentario.
Pendente: - texto da tarefa
Concluida: + texto da tarefa
Leia de cima para baixo e resolva as tarefas marcadas com "-". -->
EOF
fi

# 7. Commit inicial (rastreabilidade)
git add -A
if [ -n "$(git status --porcelain)" ]; then
  git commit -q -m "Bootstrap inicial do ambiente (diretrizes, permissoes, hook, task.md)"
fi

echo "Ambiente preparado: CLAUDE.md atualizado, permissoes aplicadas, hook de resincronizacao instalado, task.md criado, repositorio git verificado."
