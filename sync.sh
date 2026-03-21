#!/bin/bash
# Weekly auto-sync script for my-configs
# Copies iTerm2 plist (can't be symlinked), sanitizes secrets, commits & pushes

set -e
REPO="$HOME/my-configs"
cd "$REPO"

# Copy iTerm2 plist (iTerm2 rewrites this file, so symlink won't work)
plutil -convert xml1 -o "$REPO/iterm2/com.googlecode.iterm2.plist" \
  ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null || true

# Sanitize secrets from zsh files before committing
# .zprofile tokens
sed -i '' 's/glpat-[A-Za-z0-9_-]\+/<YOUR_GITLAB_TOKEN>/g' "$REPO/zsh/.zprofile" 2>/dev/null || true
sed -i '' 's/glpat-[A-Za-z0-9_.-]\+/<YOUR_GITLAB_TOKEN>/g' "$REPO/zsh/.zshrc" 2>/dev/null || true
# Atlassian tokens
sed -i '' 's/ATATT[A-Za-z0-9_=+-]\+/<YOUR_ATLASSIAN_TOKEN>/g' "$REPO/zsh/.zshrc" 2>/dev/null || true
# Generic UUIDs that look like auth tokens
sed -i '' 's/AUTH_TOKEN=[a-f0-9-]\{36\}/AUTH_TOKEN=<YOUR_ANTHROPIC_TOKEN>/g' "$REPO/zsh/.zshrc" 2>/dev/null || true

# Check for changes
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "$(date): No changes to commit"
  exit 0
fi

# Commit and push
git add -A
git commit -m "[ai:y] Auto-sync configs $(date +%Y-%m-%d)"
git push origin main

echo "$(date): Synced successfully"
