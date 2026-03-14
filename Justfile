import 'justfiles/homebrew.just'
import 'justfiles/machines.just'
import 'justfiles/kubernetes.just'

# set quiet
set dotenv-required := true
set dotenv-filename := 'k8s-on-macos.env'

# Lists recipes
default:
    just --list --unsorted