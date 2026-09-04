#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$SCRIPT_DIR"

if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

info() { printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
PesenHub Backend operational helper

Usage:
  ./run.sh [command] [argument]

Commands:
  help                         Tampilkan bantuan ini
  setup                        Periksa dependency, siapkan .env, validasi Compose
  dev                          Build dan jalankan seluruh stack, lalu cek health
  start                        Jalankan stack tanpa memaksa rebuild
  build                        Build image API dan tampilkan ukurannya
  rebuild                      Build bersih image API tanpa cache
  stop                         Hentikan container tanpa menghapusnya
  down                         Hapus container/network, pertahankan volume
  restart [api|postgres|gowa]  Restart seluruh stack atau satu service
  status                       Tampilkan status container dan ringkasan health
  logs [api|postgres|gowa]     Ikuti maksimum 100 baris awal log
  health                       Periksa endpoint live dan ready
  test                         Jalankan unit test Go
  check                        Verify module, format, vet, test, dan Compose
  fmt                          Format source Go
  migrate-up                   Terapkan seluruh migration baru
  migrate-down [--yes]         Rollback satu migration dengan konfirmasi
  migrate-status               Tampilkan versi migration tanpa mengubah database
  version                      Tampilkan versi tool dan image

Examples:
  ./run.sh setup
  ./run.sh dev
  ./run.sh logs api
  ./run.sh restart gowa
  ./run.sh migrate-down --yes
EOF
}

need_command() { command -v "$1" >/dev/null 2>&1 || die "Command '$1' tidak ditemukan."; }
need_docker() {
  need_command docker
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin tidak tersedia."
}
need_env() { [[ -f .env ]] || die ".env belum tersedia. Jalankan './run.sh setup'."; }
compose() { docker compose "$@"; }

validate_service() {
  case "${1:-}" in api|postgres|gowa) ;; *) die "Service '${1:-<kosong>}' tidak dikenal. Gunakan api, postgres, atau gowa." ;; esac
}

env_value() {
  local key="$1" fallback="$2" value
  value="$(sed -n "s/^${key}=//p" .env 2>/dev/null | tail -n 1)"
  printf '%s' "${value:-$fallback}"
}

api_base_url() {
  printf 'http://localhost:%s' "$(env_value APP_PORT 8080)"
}

container_state() {
  local service="$1" id
  id="$(compose ps -q "$service" 2>/dev/null)"
  [[ -n "$id" ]] || { printf 'absent'; return; }
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || printf 'unknown'
}

wait_ready() {
  local deadline=$((SECONDS + 60)) postgres_state api_state
  info "Menunggu PostgreSQL dan API siap (timeout 60 detik)..."
  while (( SECONDS < deadline )); do
    postgres_state="$(container_state postgres)"
    api_state="$(container_state api)"
    if [[ "$postgres_state" == "healthy" && "$api_state" == "healthy" ]]; then
      ok "PostgreSQL dan API healthy."
      return 0
    fi
    sleep 1
  done
  compose ps
  die "Timeout menunggu service: postgres=$postgres_state api=$api_state"
}

http_request() {
  local url="$1" body_file="$2" status header_file
  if command -v curl >/dev/null 2>&1; then
    status="$(curl --silent --show-error --output "$body_file" --write-out '%{http_code}' --max-time 5 "$url")" || return 1
  elif command -v wget >/dev/null 2>&1; then
    header_file="$(mktemp)"
    if ! wget --server-response --timeout=5 --output-document="$body_file" "$url" 2>"$header_file"; then
      rm -f "$header_file"
      return 1
    fi
    status="$(sed -n 's/.*HTTP\/[0-9.]* \([0-9][0-9][0-9]\).*/\1/p' "$header_file" | tail -n 1)"
    rm -f "$header_file"
  else
    die "Health check memerlukan curl atau wget."
  fi
  printf '%s' "${status:-000}"
}

json_field() {
  local field="$1" file="$2"
  sed -n "s/.*\"${field}\":\"\([^\"]*\)\".*/\1/p" "$file" | head -n 1
}

health() {
  local base tmp_live tmp_ready live_http ready_http live_status ready_status db_status gowa_status
  base="$(api_base_url)"
  tmp_live="$(mktemp)"; tmp_ready="$(mktemp)"
  if ! live_http="$(http_request "$base/health/live" "$tmp_live")"; then
    rm -f "$tmp_live" "$tmp_ready"
    die "API tidak dapat dihubungi di $base."
  fi
  if ! ready_http="$(http_request "$base/health/ready" "$tmp_ready")"; then
    rm -f "$tmp_live" "$tmp_ready"
    die "Endpoint readiness tidak dapat dihubungi di $base."
  fi
  live_status="$(json_field status "$tmp_live")"
  ready_status="$(json_field status "$tmp_ready")"
  db_status="$(json_field database "$tmp_ready")"
  gowa_status="$(json_field gowa_device "$tmp_ready")"
  rm -f "$tmp_live" "$tmp_ready"
  printf 'live:  HTTP %s, api=%s\n' "$live_http" "${live_status:-unknown}"
  printf 'ready: HTTP %s, api=%s, database=%s, gowa=%s\n' "$ready_http" "${ready_status:-unknown}" "${db_status:-unknown}" "${gowa_status:-unknown}"
  [[ "$live_http" =~ ^2 ]] || die "Liveness API gagal."
  if [[ "$ready_status" == "degraded" && "$db_status" == "up" ]]; then
    warn "API degraded karena GOWA belum siap; ini tidak fatal pada Phase 0."
    return 0
  fi
  [[ "$ready_http" =~ ^2 && "$db_status" == "up" ]] || die "Readiness API gagal."
  ok "API, database, dan readiness tersedia."
}

show_image_size() {
  docker image inspect pesenhub-api:dev --format 'image=pesenhub-api:dev size={{.Size}} bytes' || die "Image pesenhub-api:dev belum tersedia."
}

setup() {
  need_docker
  [[ -f docker-compose.yml ]] || die "docker-compose.yml tidak ditemukan di $SCRIPT_DIR."
  [[ -f .env.example ]] || die ".env.example tidak ditemukan."
  if [[ -f .env ]]; then
    ok ".env sudah tersedia; file tidak ditimpa."
  else
    cp .env.example .env
    ok ".env dibuat dari .env.example. Tinjau seluruh nilai change_me sebelum penggunaan nyata."
  fi
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    warn "curl atau wget belum tersedia; command health tidak dapat digunakan."
  fi
  compose config --quiet
  ok "Konfigurasi Docker Compose valid."
  info "Langkah berikutnya: ./run.sh dev"
  warn "Setup tidak membuat atau memasangkan device GOWA."
}

run_test() { need_command go; GOCACHE="${GOCACHE:-/tmp/pesenhub-go-cache}" go test ./...; }

run_check() {
  need_command go
  go mod verify
  local unformatted
  unformatted="$(gofmt -l .)"
  [[ -z "$unformatted" ]] || die "File Go belum terformat:$'\n'$unformatted\nJalankan './run.sh fmt'."
  GOCACHE="${GOCACHE:-/tmp/pesenhub-go-cache}" go vet ./...
  GOCACHE="${GOCACHE:-/tmp/pesenhub-go-cache}" go test ./...
  need_docker; need_env; compose config --quiet
  ok "Seluruh pemeriksaan lulus."
}

migrate() {
  local direction="$1"
  need_docker; need_env
  compose run --rm --no-deps --entrypoint /app/pesenhub-migrate api "$direction"
}

migrate_down() {
  local confirmation="${1:-}"
  [[ -z "$confirmation" || "$confirmation" == "--yes" ]] || die "Argumen migrate-down tidak valid. Gunakan --yes untuk konfirmasi eksplisit."
  if [[ "$confirmation" != "--yes" ]]; then
    [[ -t 0 ]] || die "Rollback non-interaktif ditolak. Gunakan './run.sh migrate-down --yes' jika sudah disetujui."
    printf 'Rollback satu migration? Ketik yes untuk melanjutkan: '
    read -r confirmation
    [[ "$confirmation" == "yes" ]] || die "Rollback dibatalkan."
  fi
  migrate down
}

show_version() {
  local go_version builder runtime postgres gowa
  go_version="$(sed -n 's/^go //p' go.mod | head -n 1)"
  builder="$(sed -n '1s/^FROM \([^ ]*\).*/\1/p' Dockerfile)"
  runtime="$(sed -n 's/^FROM \([^ ]*\) AS runtime$/\1/p' Dockerfile)"
  postgres="$(sed -n '/^  postgres:/,/^  [a-z]/s/^    image: //p' docker-compose.yml | head -n 1)"
  gowa="$(sed -n '/^  gowa:/,/^volumes:/s/^    image: //p' docker-compose.yml | head -n 1)"
  printf 'Go (go.mod): %s\n' "$go_version"
  if command -v docker >/dev/null 2>&1; then docker --version; docker compose version; else printf 'Docker: tidak tersedia\n'; fi
  printf 'PostgreSQL image: %s\nGOWA image: %s\nBuilder image: %s\nRuntime image: %s\nAPI image: pesenhub-api:dev\n' "$postgres" "$gowa" "$builder" "$runtime"
}

command_name="${1:-help}"
shift || true

case "$command_name" in
  help|--help|-h) [[ $# -eq 0 ]] || die "Command help tidak menerima argumen."; usage ;;
  setup) [[ $# -eq 0 ]] || die "Command setup tidak menerima argumen."; setup ;;
  dev) [[ $# -eq 0 ]] || die "Command dev tidak menerima argumen."; need_docker; need_env; compose up -d --build; compose ps; wait_ready; health; info "Lihat log dengan: ./run.sh logs api" ;;
  start) [[ $# -eq 0 ]] || die "Command start tidak menerima argumen."; need_docker; need_env; compose up -d; compose ps ;;
  build) [[ $# -eq 0 ]] || die "Command build tidak menerima argumen."; need_docker; need_env; compose build api; show_image_size ;;
  rebuild) [[ $# -eq 0 ]] || die "Command rebuild tidak menerima argumen."; need_docker; need_env; compose build --no-cache api; show_image_size ;;
  stop) [[ $# -eq 0 ]] || die "Command stop tidak menerima argumen."; need_docker; need_env; compose stop; ok "Container berhenti; network, volume, dan data dipertahankan." ;;
  down) [[ $# -eq 0 ]] || die "Command down tidak menerima argumen."; need_docker; need_env; compose down --remove-orphans; ok "Container/network dihapus; volume dan data PostgreSQL dipertahankan." ;;
  restart)
    [[ $# -le 1 ]] || die "Gunakan: ./run.sh restart [api|postgres|gowa]"
    need_docker; need_env
    if [[ $# -eq 1 ]]; then validate_service "$1"; compose restart "$1"; else compose restart; fi
    wait_ready; compose ps; health
    ;;
  status) [[ $# -eq 0 ]] || die "Command status tidak menerima argumen."; need_docker; need_env; compose ps; [[ "$(container_state api)" == "healthy" ]] && health || warn "API belum berjalan atau belum healthy." ;;
  logs)
    [[ $# -le 1 ]] || die "Gunakan: ./run.sh logs [api|postgres|gowa]"
    need_docker; need_env
    if [[ $# -eq 1 ]]; then validate_service "$1"; compose logs --follow --tail=100 "$1"; else compose logs --follow --tail=100; fi
    ;;
  health) [[ $# -eq 0 ]] || die "Command health tidak menerima argumen."; need_env; health ;;
  test) [[ $# -eq 0 ]] || die "Command test tidak menerima argumen."; run_test ;;
  check) [[ $# -eq 0 ]] || die "Command check tidak menerima argumen."; run_check ;;
  fmt) [[ $# -eq 0 ]] || die "Command fmt tidak menerima argumen."; need_command go; gofmt -w .; ok "Source Go telah diformat." ;;
  migrate-up) [[ $# -eq 0 ]] || die "Command migrate-up tidak menerima argumen."; migrate up ;;
  migrate-down) [[ $# -le 1 ]] || die "Gunakan: ./run.sh migrate-down [--yes]"; migrate_down "${1:-}" ;;
  migrate-status) [[ $# -eq 0 ]] || die "Command migrate-status tidak menerima argumen."; migrate status ;;
  version) [[ $# -eq 0 ]] || die "Command version tidak menerima argumen."; show_version ;;
  *) die "Command '$command_name' tidak dikenal. Jalankan './run.sh help'." ;;
esac
