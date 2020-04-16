#!/bin/bash
# Implement the feedback-pipeline buildroot workflow
#   f.p -> b.g. -> a.s.r. -> b.g. -> fp
#     f.p.   = feedback-pipeline
#     b.g.   = buildroot-generator
#     a.s.r. = archful source repos
#   Summary, start with a list of packages from feedback-pipeline
#     Return, as a workload, a list of packages that constitue
#     a build root for that initial set of packages.
#   This is working off the Fedora-rawhide repo.
#

#####
# Variables
#####
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source ${WORK_DIR}/conf/config.inc

PACKAGELIST_DIR="${WORK_DIR}/packagelists"
BAD_PACKAGES=(nodejs-find-up nodejs-grunt-contrib-uglify nodejs-http-errors nodejs-json-diff nodejs-load-grunt-tasks nodejs-locate-path nodejs-pkg-up nodejs-p-locate nodejs-raw-body)

## Create buildroot from feedback-pipeline packages

# Get package lists from feedback-pipeline
mkdir -p ${PACKAGELIST_DIR}
rm -f ${PACKAGELIST_DIR}/*
for this_arch in ${ARCH_LIST[@]}
do
  echo "Downloading package lists for ${this_arch}"
  wget -q -O ${PACKAGELIST_DIR}/Packages.${this_arch} https://tiny.distro.builders/view-binary-package-name-list--eln-compose--${this_arch}.txt
  wget -q -O ${PACKAGELIST_DIR}/Sources.${this_arch} https://tiny.distro.builders/view-source-package-list--eln-compose--${this_arch}.txt
done

# Generate the initial buildroot
./buildroot-generator -r rawhide -p ${PACKAGELIST_DIR}

# Take the initial buildroot and create archful source repos
./identify-archful-srpms
./create-srpm-repos

# (Optional) Save off initial buildroot lists
#   Not written yet, cuz it's optional

# Generate the final buildroot using the archful source repos
rm -f ${REPO_DIR}/rawhide-archful-source.repo
cp ${REPO_DIR}/rawhide-archful-source.repo.template ${REPO_DIR}/rawhide-archful-source.repo
sed -i "s|BASE-DIR|${WORK_DIR}|" ${REPO_DIR}/rawhide-archful-source.repo
./buildroot-generator -r rawhide-archful-source -p ${PACKAGELIST_DIR}


## Create buildroot workload and upload it to feedback-pipeline

# Determine binary packages added, and which are arch specific
rm -f ${PACKAGELIST_DIR}/Packages.added.tmp
for this_arch in ${ARCH_LIST[@]}
do
  DATA_DIR="${DATA_DIR_BASE}/${this_arch}"
  comm -13 ${DATA_DIR}/${NEW_DIR}/Packages.${this_arch} ${DATA_DIR}/${NEW_DIR}/buildroot-binary-package-names.txt | sort -u -o ${DATA_DIR}/${NEW_DIR}/added-binary-package-names.txt
  cat ${DATA_DIR}/${NEW_DIR}/added-binary-package-names.txt >> ${PACKAGELIST_DIR}/Packages.added.tmp
done
cat ${PACKAGELIST_DIR}/Packages.added.tmp | sort | uniq -cd | sed -n -e 's/^ *4 \(.*\)/\1/p' | sort -u -o ${PACKAGELIST_DIR}/Packages.added.common

# Generate the buildroot workload
rm -f ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
cat ${WORK_DIR}/conf/eln-buildroot-workload.head >> ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
cat ${PACKAGELIST_DIR}/Packages.added.common | awk '{print "        - " $1}' >> ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
echo "    arch_packages:" >> ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
for this_arch in ${ARCH_LIST[@]}
do
  DATA_DIR="${DATA_DIR_BASE}/${this_arch}"
  echo "        ${this_arch}:" >> ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
  comm -13 ${PACKAGELIST_DIR}/Packages.added.common ${DATA_DIR}/${NEW_DIR}/added-binary-package-names.txt | awk '{print "            - " $1}' >> ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
done

# Trim buildroot workload of packages we don't want in there
for pkgname in ${BAD_PACKAGES[@]}
do
  sed -i "/ ${pkgname}$/d" ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml
done

# Upload to feedback-pipeline
if ! [ -d ${GIT_DIR}/feedback-pipeline-config ] ; then
  mkdir -p ${GIT_DIR}
  cd ${GIT_DIR}
  git clone git@github.com:minimization/feedback-pipeline-config.git
fi
cd ${GIT_DIR}/feedback-pipeline-config
git pullcp 
cp ${PACKAGELIST_DIR}/eln-buildroot-workload.yaml .
git add eln-buildroot-workload.yaml
git commit -m "Update eln-buildroot-workload $(date +%Y-%m-%d-%H:%M)"
#git push

exit 0

