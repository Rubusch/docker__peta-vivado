#!/bin/sh -e
DRYRUN="${1}"
UID="$(id -u)"
GID="$(id -g)"
USER="$(whoami)"

die()
{
	echo "FAILED! $@."
	exit 1
}

## MAIN
if [ -d ".git" ]; then
	## if this is a git repo, check if we're on branch "main", then abort
	if [ "main" = "$( git rev-parse --abbrev-ref HEAD )" ]; then
		die "THIS IS MAIN, PLEASE CHANGE TO ONE OF THE GIT BRANCHES"
	fi
fi

test -z "${DOCKERDIR}" && DOCKERDIR="docker"
test -z "${DOWNLOADDIR}" && DOWNLOADDIR="download"
TOPDIR="$(pwd)"
IMAGE="$( grep "^FROM" -HIrn ${DOCKERDIR}/build_context/Dockerfile | awk '{ print $NF }' )"
VERSION="$( echo ${IMAGE} | awk -F'-' '{ if ($NF == "nightly") {print $(NF-1)} else {print $NF} }' )"
CONTAINER="$( docker images -q ${IMAGE} 2> /dev/null )" || true
if [ -z "${CONTAINER}" ]; then
	## container is not around, build
	DO_BUILD=1
else
	## container around, start
	cd "${DOCKERDIR}"
        APP="/bin/bash"
        if [ ! -e .env ]; then
            APP=""
	    echo "UID=$(id -u)" > .env
	    echo "GID=$(id -g)" >> .env

            echo
            echo "Preparing docker images - please re-run this script to enter the container image!"
        fi

	docker run \
	       --rm \
               --net host \
               --name ${IMAGE} \
               -u ${UID}:${GID} \
               -it \
               --privileged \
               -e USER \
               -e DISPLAY=$DISPLAY \
               --env-file .env \
               --group-add 20 \
               --mount type=bind,source=./build_configs,target=/home/$USER/configs \
               -v /tmp/.X11-unix:/tmp/.X11-unix \
               -v ~/.Xauthority:/home/${USER}/.Xauthority:ro \
               -v ~/.gitconfig:/home/${USER}/.gitconfig:ro \
               -v ~/.ssh:/home/${USER}/.ssh \
               -v ./workspace:/home/${USER}/workspace \
               ${CONTAINER} \
               ${APP}

	exit 0
fi

if [ -n "${DO_BUILD}" ]; then
	DATE="$(date +%Y%m%d%H%M)"
	if [ -z "${XILINXMAIL}" ]; then
		die "env variable XILINXMAIL is not set"
	fi
	if [ -z "${XILINXLOGIN}" ]; then
		die "env variable XILINXLOGIN is not set"
	fi

	test -f ${TOPDIR}/${DOWNLOADDIR}/petalinux-v${VERSION}-*-installer.run || die "No petalinux installer provided! Please, put a petalinux-v${VERSION}-*-installer.run  in '${TOPDIR}/${DOWNLOADDIR}'"
	test -f ${TOPDIR}/${DOWNLOADDIR}/Xilinx_Unified_${VERSION}_*_Lin64.bin || die "No Xilinx_Unified_${VERSION}_*_Lin64.bin file provided in '${TOPDIR}/${DOWNLOADDIR}'"

	mv ${TOPDIR}/${DOWNLOADDIR}/petalinux-v${VERSION}-*-installer.run "${TOPDIR}/${DOCKERDIR}/build_context/"
	mv ${TOPDIR}/${DOWNLOADDIR}/Xilinx_Unified_${VERSION}_*_Lin64.bin "${TOPDIR}/${DOCKERDIR}/build_context/"

        cd "$DOCKERDIR"
	docker build \
               --tag ${IMAGE}:${DATE} \
               --build-arg UID=${UID} \
               --build-arg GID=${GID} \
               --build-arg USER=${USER} \
               --build-arg XILINXMAIL=${XILINXMAIL} \
               --build-arg XILINXLOGIN=${XILINXLOGIN} \
               ./build_context
	cd "${TOPDIR}/${DOCKERDIR}"
fi

echo "READY."
