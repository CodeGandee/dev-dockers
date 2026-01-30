DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" 
echo "Executing $DIR/_custom-on-build.sh" 
bash $DIR/../../stage-1/custom/install-apt-packages.sh
bash $DIR/../../stage-1/custom/install-uv.sh