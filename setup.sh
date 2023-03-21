#!/bin/sh -e
## builds the container, or if already built, logs into the build environment
DRYRUN="${1}"

die()
{
	echo "FAILED! $@."
	exit 1
}

do_env()
{
	echo "UID=$(id -u)" > .env
	echo "GID=$(id -g)" >> .env
}

build()
{
	CONTAINER_NAME="$(grep "container_name:" -r "${1}/docker-compose.yml" | awk -F: '{ print $2 }' | tr -d ' ')"
	cd "${1}"
	if [ -n "${2}" ]; then
		docker-compose build -d --remove-orphans
	else
		docker-compose up -d --remove-orphans --exit-code-from "${CONTAINER_NAME}"
	fi
	cd -
}

link()
{
	src="${1}"
	dst="${2}"
	test -f "${src}" || die "file '${src}' is missing or not accessable"
	cd "${dst}"
	ln -s "${src}" .
	cd -
}

TOPDIR="$(pwd)"
test -z "${DOCKERDIR}" && DOCKERDIR="docker"
test -z "${DOWNLOADDIR}" && DOWNLOADDIR="download"
BASE_IMAGE="$(grep "ARG DOCKER_BASE=" -r "${DOCKERDIR}/build_context/Dockerfile" | awk -F= '{ print $2 }' | tr -d '"')"
BASE_IMAGE_TAG="$(grep "ARG DOCKER_BASE_TAG" -r "${DOCKERDIR}/build_context/Dockerfile" | awk -F= '{ print $2 }' | tr -d '"')"
IMAGE="$( grep "^FROM" -HIrn ${DOCKERDIR}/build_context/Dockerfile | awk '{ print $NF }' )"
VERSION="$( echo ${IMAGE} | awk -F'-' '{print $NF}' )"

## NB: check for particular user, when different user prefixed images are around

## decide or start existing container
CONTAINER="$(docker images | grep "${BASE_IMAGE}" | grep "${BASE_IMAGE_TAG}" | awk '{print $3}')" || true
if [ -z "${CONTAINER}" ]; then
	## base not around, build
	DO_BUILDBASE=1
	DO_BUILD=1
        test -f ${TOPDIR}/${DOWNLOADDIR}/Xilinx_Unified_${VERSION}_*_Lin64.bin || die "No Xilinx_Unified_${VERSION}_*_Lin64.bin file provided in '${TOPDIR}/${DOWNLOADDIR}'"
else
	CONTAINER="$( docker images | grep "${IMAGE}" | awk '{print $3}' )" || true
	if [ -z "${CONTAINER}" ]; then
		## container is not around, build
		DO_BUILD=1
	else
		## container around, start
		cd "${DOCKERDIR}"
	
		if [ ! -f .env ]; then
			echo "WARNING: no .env set, trying to obtain provided file"
			link "${TOPDIR}/${DOWNLOADDIR}"/.env .
		fi
		docker-compose -f ./docker-compose.yml run --rm "${IMAGE}" /bin/bash
	
		## exit success
		exit 0
	fi
fi

## checks
if [ -n "${DO_BUILDBASE}" ]; then
	test -f ${TOPDIR}/${DOWNLOADDIR}/petalinux-v${VERSION}-*-installer.run || die "No petalinux installer provided! Please, put a petalinux-v${VERSION}-*-installer.run  in '${TOPDIR}/${DOWNLOADDIR}'"
fi

if [ -n "${DO_BUILD}" ]; then
	test -f ${TOPDIR}/${DOWNLOADDIR}/Xilinx_Unified_${VERSION}_*_Lin64.bin || die "No Xilinx_Unified_${VERSION}_*_Lin64.bin file provided in '${TOPDIR}/${DOWNLOADDIR}'"
fi

## build (slow)
if [ -n "${DO_BUILDBASE}" ]; then
	git clone "https://github.com/Rubusch/docker__petalinux.git" "${BASE_IMAGE}" || die "Could not clone petalinux repo"
	cd "${BASE_IMAGE}"
	git checkout "${BASE_IMAGE_TAG}"
	link "${TOPDIR}/${DOWNLOADDIR}"/.env ./docker/
	mv ${TOPDIR}/${DOWNLOADDIR}/petalinux-v${VERSION}-*-installer.run "./docker/build_context/"
	./setup.sh "build"
	cd "${TOPDIR}"
fi
if [ -n "${DO_BUILD}" ]; then
	link "${TOPDIR}/${DOWNLOADDIR}"/.env "${TOPDIR}/${DOCKERDIR}"/
	mv ${TOPDIR}/${DOWNLOADDIR}/Xilinx_Unified_${VERSION}_*_Lin64.bin "${TOPDIR}/${DOCKERDIR}/build_context"
	build "${DOCKERDIR}" "${DRYRUN}"
	cd "${TOPDIR}/${DOCKERDIR}"
	echo "!!! Docker finished, overwrite ${DOCKERDIR}/.env file with default user, in case adjust manually !!!"
	do_env
fi

echo "READY."
