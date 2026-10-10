cd /d/ATLAS-DATA/dashboard-kas
echo "=== GIT LOG (index.html) ==="
for C in $(git log --format='%h' -- index.html | head -20); do
  H=$(git show $C:index.html 2>/dev/null)
  REG=$(printf '%s' "$H" | grep -c 'serviceWorker.register')
  DIAG=$(printf '%s' "$H" | grep -c 'serverDiagnostic')
  LOCAL=$(printf '%s' "$H" | grep -c '127.0.0.1')
  TOK=$(printf '%s' "$H" | grep -c 'me.token')
  SELF=$(printf '%s' "$H" | grep -c 'SELF-HEAL')
  printf '%s  regSW=%s  diag=%s  localhost=%s  meTok=%s  selfheal=%s\n' "$C" "$REG" "$DIAG" "$LOCAL" "$TOK" "$SELF"
done
echo
echo "=== SW FILES per commit ==="
for C in $(git log --format='%h' -- sw.js | head -6); do
  CACHE=$(git show $C:sw.js 2>/dev/null | grep -o "CACHE *= *'[^']*'" | head -1)
  STRAT=$(git show $C:sw.js 2>/dev/null | grep -c 'NETWORK-FIRST')
  printf '  %s  %s  networkfirst=%s\n' "$C" "$CACHE" "$STRAT"
done