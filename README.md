# my-configs

Personal terminal and shell configurations.

## Structure

```
ghostty/     # Ghostty terminal config
iterm2/      # iTerm2 preferences (plist)
zsh/         # Zsh shell configs (.zshrc, .zprofile)
```

## Setup

**Ghostty:**
```bash
ln -sf $(pwd)/ghostty/config ~/.config/ghostty/config
```

**Zsh:**
```bash
ln -sf $(pwd)/zsh/.zshrc ~/.zshrc
ln -sf $(pwd)/zsh/.zprofile ~/.zprofile
```

**iTerm2:**
Set iTerm2 > Preferences > General > Preferences to load from this repo's `iterm2/` directory.
