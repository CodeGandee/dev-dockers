DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
echo "Executing $DIR/_custom-on-build.sh" 
bash $DIR/../../stage-2/system/pixi/install-pixi.bash --user me --conda-repo tuna --pypi-repo tuna
bash $DIR/../../stage-2/system/litellm/install-litellm.sh --user me
bash $DIR/../../stage-2/system/nodejs/install-nvm-nodejs.sh --user me
bash $DIR/../../stage-2/system/bun/install-bun.sh --user me --npm-repo https://registry.npmmirror.com
bash $DIR/../../stage-2/system/claude-code/install-claude-code.sh --user me
bash $DIR/../../stage-2/system/codex-cli/install-codex-cli.sh --user me