#!/bin/bash

SATMUT_UTILS_REPO="https://github.com/CenikLab/satmut_utils.git"

SATMUT_UTILS_REFS_REPO="https://github.com/CenikLab/satmut_utils_refs.git"

# FTP link to Ensembl-formatted genome 
GENOME_URL="ftp://ftp.ensembl.org/pub/release-84/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz"

usage() {
cat << EOF  
Usage: ./install_satmut_utils [-htg] [-r <REF_DIR>] <SATMUT_ROOT>
Install satmut_utils and download reference files.

-h	Help
-t	Download curated human transcriptome files
-g	Download human genome FASTA
-r REF_DIR	Download files to REF_DIR

EOF
}

while getopts ":tgr:" o; do
	case "${o}" in
		t)
			GET_TRANSCRIPTOME="True"
			;;
		g)
			GET_GENOME="True"
			;;
		r)
			REF_DIR=${OPTARG}
			;;
		*)
			usage
			exit
			;;
	esac
done
shift $((OPTIND-1))

echo "Started $0"

if [ "$1" == "" ]; then
	echo "Please provide a valid satmut_utils root directory as the first positional argument."
	exit 1
fi

# Need miniconda for managing environments and packages. 
if [ ! -x $(which conda) ]
then
	echo "conda required. See https://docs.conda.io/en/latest/miniconda.html for installation."
	exit
fi

# Create and activate the conda environment
if conda env list | fgrep "satmut_utils " >/dev/null 2>&1
then
	echo "satmut_utils environment already exists. If you would like to regenerate the environment, remove it first with \"conda env remove --name satmut_utils\""
	exit 1
else
	echo "Creating satmut_utils environment."
	SATMUT_CONFIG=$1/satmut_utils_env.yaml
	conda env create -f "$SATMUT_CONFIG"
fi

# See https://github.com/conda/conda/issues/7980
# Need to source the proper conda config directly as
# the subshell will not source .bashrc
CONDA_BASE=$(conda info --base)
CONDA_CONFIG=${CONDA_BASE%%/}/etc/profile.d/conda.sh

conda init bash
source $CONDA_CONFIG
conda activate satmut_utils

if [[ -z "$REF_DIR" && ( "$GET_TRANSCRIPTOME" || "$GET_GENOME" ) ]]
then
REF_DIR=$(mktemp -d -t satmut_utils_refs_XXXXXXXXXX)
fi

if [ ! -z "$GET_TRANSCRIPTOME" ]
then
	mkdir -p "$REF_DIR"
	echo "Getting curated human transcriptome files and writing to $REF_DIR"
	cd "$REF_DIR"
	git clone $SATMUT_UTILS_REFS_REPO
	mv satmut_utils_refs/* $REF_DIR && gunzip $REF_DIR/*gz
fi

if [ ! -z "$GET_GENOME" ]
then
	mkdir -p "$REF_DIR"
	echo "Downloading human genome FASTA and writing to $REF_DIR"
	curl -L -R -o $REF_DIR/GRCh38.fa.gz $GENOME_URL
	echo "bgzipping genome FASTA and indexing"
	gunzip $REF_DIR/GRCh38.fa.gz && bgzip $REF_DIR/GRCh38.fa
	samtools faidx $REF_DIR/GRCh38.fa.gz
fi

echo "To use satmut_utils, activate the conda environment with \"conda activate satmut_utils\"."

echo "Completed $0"
