# Checks dependecies of bundled homebrew packages
[group('homebrew')]
bundle-check:
    -@brew bundle check

# Lists bundled homebrew packages (formulaes, casks and taps)
[group('homebrew')]
bundle-list:
    @echo '{{ GREEN }}[ Tapped 3rd party repositories ]{{ NORMAL }}'
    @brew bundle list --tap --quiet
    @echo '{{ GREEN }}[ Installed casks ]{{ NORMAL }}'
    @brew bundle list --cask --quiet
    @echo '{{ GREEN }}[ Installed formulaes ]{{ NORMAL }}'
    @brew bundle list --formulae --quiet

# Installs or upgrades bundled homebrew formulaes, casks and taps
[group('homebrew')]
bundle-install:
    @brew bundle install --upgrade