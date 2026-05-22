
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


source <(grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Z_][A-Z0-9_]*=' "$SCRIPT_DIR/.env")
echo bla
