#!/usr/bin/env bash

# Title: Make-dataset from demultiplexed 16S rRNA V3V4 PE-seqs fastq
# Author: Marco Prevedello
# Date: 2019-05-07

## Get script location
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
projectDir="$( cd $scriptDir/.. && pwd )"

## Perform basic check
if [[ ! $scriptDir =~ /src$ ]] || [[ ! -d $projectDir/data/raw ]]; then
   echo "You are not using the expected folder structure. This script cannot work. Please read the README file before proceeding."
   [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

## Output essential information
echo
echo "--- IMPORTANT USER INFORMATION ---"
echo
echo "This script is designed for demultiplexed double paired-end reads."
echo "If you are working with single paired-end reads modify the script accordingly"
echo "If you have NOT demultiplexed reads, be sure to demultiplex first!"
echo "This script require a conda QIIME2-2019.4  environment. If you haven't configured it yet, please configure it first (see the script init-qiime-2019.4-env.sh)."
echo "Be sure to read the README file before proceeding"
echo "For questions check the documentation in the ./doc folder"
echo
echo "qiime2-2019.4 is used for its unique trimming function."
echo "Further info here: https://github.com/qiime2/q2-cutadapt/issues/10"
echo "Load conda environment for QIIME2 analysis PRIOR to running this script!"
echo
read -t 100 -p "Terminate the script now?[y/n] " -n 1 -r
if [[ $REPLY =~ ^[Yy] ]]; then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

## Basic variables definition
qiimeView="https://view.qiime2.org/"
rawData=$projectDir/data/raw

## Ensure destination folders
logsDir=$projectDir/logs
outputDir=$projectDir/data/interim
mkdir -p $logsDir
mkdir -p $outputDir
echo
echo "The log report of the computation can be found in $logsDir"
echo
echo "The output of the computation can be found in $outputDir"

## Import paired-end fastq into a qiime2 object
echo
echo "Importing de-multiplexed paired-end reads with quality (FASTQ) from $rawData into QIIME2"

time qiime tools import \
     --type 'SampleData[PairedEndSequencesWithQuality]' \
     --input-path $rawData/fastq-reads/ \
     --input-format CasavaOneEightSingleLanePerSampleDirFmt \
     --output-path $outputDir/demux-seqs.qza

## Summarize raw reads
time qiime demux summarize \
     --i-data $outputDir/demux-seqs.qza \
     --o-visualization $outputDir/demux-seqs.qzv

echo
echo "Data import have finished. A summary of the reads can be visualised at $qiimeView uploading the file $outputDir/demux-seqs.qzv"

## Trim FASTQ files using q2-cutadapt trim
echo
echo "  ---  TRIMMING WITH q2-CUTADAPT  ---  "

i=0
while [[ $i == 0 ]]; do
    echo
    echo "Trimming out adapters from the imported reads.  Provide sequence of the adapter ligated to the 5' end.  If nothing is provided, the standard KU-MME adapters are considered."
    echo
    read -t 120 -p "Adapter to search in FORWARD read: " adapterF
    echo
    read -t 120 -p "Adapter to search in REVERSE read: " adapterR

    if [[ -z $adapterF ]]; then adapterF=CCTAYGGGRBGCASCAG; fi
    if [[ -z $adapterR ]]; then adapterR=GGACTACHVGGGTWTCTAAT; fi

    echo
    echo "The selected FORWARD adapter is: $adapterF"
    echo
    echo "The selected REVERSE adapter is: $adapterR"
    echo
    read -t 60 -p "Do you wish to change them?[y/n] " -n 1 -r
    if [[ ! $REPLY =~ [yY] ]]; then i=1; fi
done

time qiime cutadapt trim-paired \
     --i-demultiplexed-sequences $outputDir/demux-seqs.qza \
     --p-cores 3 \
     --p-front-f  $adapterF \
     --p-front-r $adapterR \
     --p-error-rate 0.1 \
     --p-indels \
     --p-discard-untrimmed \
     --o-trimmed-sequences $outputDir/trimmed-demux-seqs.qza \
     --verbose 2>&1 | tee $logsDir/01_trimming.log

## Summarize trimmed reads
time qiime demux summarize \
     --i-data $outputDir/trimmed-demux-seqs.qza \
     --o-visualization $outputDir/trimmed-demux-seqs.qzv

echo "The trimmed reads are saved as $outputDir/trimmed-demux-seqs.qza"
echo "A summary of the trimming step can be visualised at $qiimeView uploading the file $outputDir/trimmed-demux-seqs.qzv"

## Denoise with DADA2
echo
echo "  ---  DENOISE WITH DADA2  ---  "
echo
echo "Accordingly with Callahan et al. (2017), this workflow uses amplicon sequence variants (ASVs) instead of operational taxonomical units (OTUs). Refer to the cited paper for explanations."
echo
echo "To produce ASVs, the trimmed reads will be denoised using DADA2."
echo "If you wish to use Deblur, see here https://docs.qiime2.org/2019.4/tutorials/read-joining/?highlight=deblur and modify this script accordingly."
echo

dada2Dir=$outputDir/dada2-denoise
mkdir -p $dada2Dir
echo
echo "The output produced by DADA2 denoise pipeline will be saved in $dada2Dir"

i=0
while [[ $i == 0 ]]; do
    echo
    echo "The forward and reverse reads are truncated at the 3' end due to decrease in quality at 275 and 250 nt respectively. If you wish to change this behaviour input a new value. See the QIIME2 manual for further information."
    echo
    read -t 120 -p "Forward read 3' truncation length[0-500]: (DEFAULT:275) " trunF
    echo
    read -t 120 -p "Reverse read 3' truncation length[0-500]: (DEFAULT:250) " trunR

    if [[ -z $trunF ]]; then trunF=275; fi
    if [[ $trunF -gt 500 ]]; then echo "The value of forward read 3' truncation ($trunF) is outside the suggested range"; fi
    if [[ -z $trunR ]]; then trunR=250; fi
    if [[ $trunR -gt 500 ]]; then echo "The value of reverse read 3' truncation ($trunR) is outside the suggested range"; fi
    echo
    echo "The selected FORWARD truncation length is: $trunF"
    echo
    echo "The selected REVERSE truncation length is: $trunR"
    echo
    read -t 60 -p "Do you wish to change them?[y/n] " -n 1 -r
    if [[ ! $REPLY =~ [yY] ]]; then i=1; fi
done

i=0
while [[ $i == 0 ]]; do
    echo
    echo "Similarly, the forward and reverse reads are trimmed at the 5' due to decreade in quality at 5 nt. If you wish to change this behaviour input a new value."
    echo
    read -t 120 -p "Forward read 5' trim length[0-50]: (DEFAULT:5) " trimF
    echo
    read -t 120 -p "Reverse read 5' trim length[0-50]: (DEFAULT:5) " trimR

    if [[ -z $trimF ]]; then trimF=5; fi
    if [[ $trunF -gt 50 ]]; then
        echo "The value of forward read 5' trim ($trimF) is outside the suggested range"
    fi
    if [[ -z $trimR ]]; then trimR=5; fi
    if [[ $trunR -gt 50 ]]; then
        echo "The value of reverse read 5' trim ($trimR) is outside the suggested range"
    fi

    echo
    echo "The selected FORWARD 5' trim length is: $trimF"
    echo
    echo "The selected REVERSE 5' trim length is: $trimR"
    echo
    read -t 60 -p "Do you wish to change them?[y/n] " -n 1 -r
    if [[ ! $REPLY =~ [yY] ]]; then i=1; fi
done

echo
echo "To visualise the correlation between metadata and denoised reads a metadata file must be provided."
echo "If you don't have a metadata file yet you can terminate the script now"
read -t 60 -p "Do you wish to terminate the script?[y/n] "
if [[ $REPLY =~ ^[Yy]$ ]]; then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

i=0
while [[ $i == 0 ]]; do
    read -t 120 -p "Metadata file path: (DEFAULT: $projectDir/data/metadata.tsv) " metadata
    if [[ -z $metadata ]]; then metadata=$projectDir/data/metadata.tsv; fi
    if [[ $metadata =~ /$ ]]; then metadata=${metadata%\/}; fi
    if [[ $metadata =~ ^~ ]]; then metadata=$HOME/${metadata#\~}; fi
    metadata=${metadata/\/\//\/}

    if [[ ! -r $metadata ]] || [[ ! -s $metadata ]]; then
        echo
        echo "The supplied metadata file is either non-readable, empty, or missing."
        echo "Ensure that the correct metadata file path is given"
        echo "Your input was $metadata"
        i=0
    else
        echo "The following metadata file will be used:"
        echo $metadata
        read -t 60 -p "Do you wish to change it?[y/n] " -n 1 -r
        if [[ $REPLY =~ [yY] ]]; then i=0; else i=1; fi
    fi
done

echo
echo "DADA2 denoising is running..."
echo "..."
echo "Be patient"
time qiime dada2 denoise-paired \
     --i-demultiplexed-seqs $outputDir/trimmed-demux-seqs.qza \
     --p-trunc-len-f $trunF \
     --p-trunc-len-r $trunR \
     --p-trim-left-f $trimF \
     --p-trim-left-r $trimR \
     --p-n-threads 0 \
     --o-table $dada2Dir/table.qza \
     --o-representative-sequences $dada2Dir/rep-seqs.qza \
     --o-denoising-stats $dada2Dir/denoising-stats.qza \
     --verbose 2>&1 | tee $logsDir/02_dada2.log

table=$dada2Dir/table.qza
repSeqs=$dada2Dir/rep-seqs.qza

echo
echo "..."
echo "Summarizing the feature cont..."
## Adding metadata and visualize feature count table
time qiime feature-table summarize \
     --i-table $dada2Dir/table.qza \
     --m-sample-metadata-file $metadata \
     --o-visualization $dada2Dir/table-summarize.qzv \
     --verbose 2>&1 | tee $logsDir/03_metadata-merge.log

time qiime feature-table tabulate-seqs \
     --i-data $dada2Dir/rep-seqs.qza \
     --o-visualization $dada2Dir/rep-seqs-mapping.qzv \
     --verbose 2>&1 | tee $logsDir/04_tabulate-seqs.log

echo
echo "Done!"
echo "Reads count, distribution and other statistical summaries are abailable at $dada2Dir/table-summarize.qzv"
echo
echo "Feature IDs to sequences mapping for BLAST search is available at $dada2Dir/rep-seqs-mapping.qzv"

echo
echo "Denoising have finished. Check $logsDir/dada2.log and the produced output at $dada2Dir"

## Create rooted phylogenetic tree
echo
echo "The script will now create a phylogenetic tree"
echo "Several methods can be used to create a tree. Check this reference: https://forum.qiime2.org/t/q2-phylogeny-community-tutorial/4455"
echo
echo "Briefly, you can choose:"
echo "1) mafft-fasttree pipeline: quick and dirty de-novo tree reconstruction (1-2 mins) (DEFAULT)"
echo
echo "2) iqtree-ultrafast-bootstrap: bootstrap (1000X) validated de-novo tree (30-35 mins)"
echo
echo "3) q2-fragment-insertion: fragment-insertion on a reference phylogenetic tree. (3-7 days)"
echo
read -t 60 -p "Do you wish to terminate the script here??[y/n] " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

i=0
while [[ $i == 0 ]]; do
    read -t 100 -p "Select method:[1/2/3] DEFAULT:3 " treeMethod
    if [[ ! $treeMethod =~ [1-3] ]]; then treeMethod=3; fi

    if [[ $treeMethod == 1 ]]; then
        i=1
        treeDir=$outputDir/mafft-fasttree
        rootedTree=$treeDir/rooted-tree.qza
        mkdir -p $treeDir

        time qiime phylogeny align-to-tree-mafft-fasttree \
             --i-sequences $dada2Dir/rep-seqs.qza \
             --p-n-threads 0 \
             --p-mask-max-gap-frequency 1 \
             --p-mask-min-conservation 0.4 \
             --o-alignment $treeDir/aligned-rep-seqs.qza \
             --o-masked-alignment $treeDir/masked-aligned-rep-seqs.qza \
             --o-tree $treeDir/tree.qza \
             --o-rooted-tree $rootedTree \
             --verbose 2>&1 | tee $logsDir/05_mafft-fastree.log

    elif [[ $treeMethod == 2 ]]; then
        i=1
        treeDir=$outputDir/iqtree
        rootedTree=$treeDir/rooted-tree.qza
        mkdir -p $treeDir

        ### Align seqs
        time qiime alignment mafft \
             --i-sequences $dada2Dir/rep-seqs.qza \
             --p-n-threads 0 \
             --o-alignment $treeDir/aligned-rep-seqs.qza \
             --verbose 2>&1 | tee $logsDir/05_mafft-alignment.log

        ### Mask aligned seqs
        time qiime alignment mask \
             --i-alignment $treeDir/aligned-rep-seqs.qza \
             --p-max-gap-frequency 1 \
             --p-min-conservation 0.4 \
             --o-masked-alignment $treeDir/masked-aligned-rep-seqs.qza \
             --verbose 2>&1 | tee $logsDir/06_mask-alignment.log

        ### Create unrooted tree
        time qiime phylogeny iqtree-ultrafast-bootstrap \
             --i-alignment $treeDir/masked-aligned-rep-seqs.qza \
             --p-seed 42 \
             --p-n-cores 0 \
             --p-n-runs 25 \
             --p-substitution-model MFP \
             --p-bootstrap-replicates 1000 \
             --p-stop-iter 200 \
             --p-perturb-nni-strength 0.2 \
             --p-bnni \
             --o-tree $treeDir/UFboot-nni-iqtree.qza \
             --verbose 2>&1 | tee $logsDir/07_iqtree-ultrafast-bootstrap.log

        ### Midpoint rooting
        time qiime phylogeny midpoint-root \
             --i-tree $treeDir/UFboot-nni-iqtree.qza \
             --o-rooted-tree $rootedTree \
             --verbose 2>&1 | tee $logsDir/08_midpoint-root.log

    elif [[ $treeMethod == 3 ]]; then
        i=1
        treeDir=$outputDir/sepp-tree
        rootedTree=$treeDir/rooted-tree.qza
        filteredtable=$outputDir/sepp-filtered-table
        mkdir -p $treeDir $filteredtable

        echo
        echo "This tree will be built upon the Greengenes 13_8 99% tree"
        echo "Other reference trees are not currently supported by this script, BUT allowed by QIIME2."
        echo "If you wish to change this behaviour, edit this script or run the fragment-insertion sepp separately."
        echo
        read -t 60 -p "Do you wish to terminate the script here?[y/n] " -n 1 -r
        if [[ $REPLY =~ [yY] ]]; then
            [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
        fi

        time qiime fragment-insertion sepp \
             --i-representative-sequences $dada2Dir/rep-seqs.qza \
             --p-threads 3 \
             --o-tree $rootedTree \
             --o-placements $treeDir/insertion-placements.qza \
             --verbose 2>&1 | tee $logsDir/05_fragment-insertion-sepp.log

        time qiime fragment-insertion filter-features \
             --i-table $dada2Dir/table.qza \
             --i-tree $rootedTree \
             --o-filtered-table $filteredtable/sepp-filtered-table.qza \
             --o-removed-table $filteredtable/sepp-removed-table.qza \
             --verbose 2>&1 | tee $logsDir/06_fragment-insertion-filter.log

    fi
done

## Taxonomical classification
echo
echo "The reads will be now mapped to their respective taxonomy based on a supplied trained classifier [*.qza]. If no input is provided, the default MiDAS 123 classifier trained on the V3V4 region with primers 314F/806R is used."
echo

i=0
while [[ $i == 0 ]]; do
    read -t 200 -p "Full path of the trained classifier:[*.qza] " classifier

    if [[ $classifier =~ ^~ ]]; then classifier=$HOME/${classifier#\~}; fi
    if [[ $classifier =~ /$ ]]; then classifier=${classifier%\/}; fi
    classifier=${classifier/\/\//\/}

if [[ ! $classifier =~ (.qza)$ ]]; then
    classifier=$outputDir/MiDAS_S123_2.1.3-trained.qza
    fi

    echo
    echo "The $classifier classifier will be used"
    read -t 60 -p "Do you wish to change this?[y/n] " -n 1 -r
    if [[ ! $REPLY =~ [yY] ]]; then i=1; fi
done

classifierName=${classifier##*/}
classifierName=${classifierName%.qza}
taxonomyDir=$outputDir/$classifierName-taxonomy
mkdir -p $taxonomyDir

time qiime feature-classifier classify-sklearn \
     --i-classifier $classifier \
     --i-reads $dada2Dir/rep-seqs.qza \
     --o-classification $taxonomyDir/taxonomy.qza \
     --verbose 2>&1 | tee $logsDir/09_$classifierName-taxonomy.log

time qiime metadata tabulate \
     --m-input-file $taxonomyDir/taxonomy.qza \
     --o-visualization $taxonomyDir/taxonomy.qzv

## Collectors curves
collectorsDir=$outputDir/collectors-curves
mkdir -p $collectorsDir

echo
echo "The script will now compute the collectors curves, also known as alpha-rarefaction curves. These display if the obtained sequencing depth is high enough to assess the sample aslpha -diversity (richness, FD, H')"
echo "A maximum rarefaction depth is required. This value should be similar to the median of the “Frequency per sample” value presented in the $dada2Dir/table.qzv file."
echo "If no input is provided, the default of 20000 will be used"

echo
read -t 120 -p "Which max rarefaction depth should be used?[4000-50000] " maxDepth
if [[ -z $maxDepth ]] || [[ $maxDepth -lt 4000 ]] || [[ $maxDepth -gt 50000 ]]; then
    maxDepth=20000
fi

time qiime diversity alpha-rarefaction \
     --i-table $table \
     --i-phylogeny $rootedTree \
     --p-max-depth $maxDepth \
     --m-metadata-file $metadata \
     --o-visualization $collectorsDir/alpha-rarefaction.qzv \
     --verbose 2>&1 | tee $logsDir/10_collectors-curves.log

## Export for R (PhyloSeq) workflow (OPTIONAL)
echo
echo "The feature table with and without taxonomy, the phylogenetic tree, and the representative sequences can exportet to BIOM files, nwk tree, and fasta sequences respectively. Hence, allowing further data analysis outside of QIIME2 (e.g., with the PhyloSeq R package)."
echo
read -t 120 -p "Do you wish to skip the export step?[y/n] (DEFAULT: No) " -n 1 -r
if [[ $REPLY =~ [yY] ]]; then
    echo
    echo "The \"Make Dataset\" workflow is finished."
    echo "You can export the QIIME2 features with the command \"qiime tools export\""
    echo "Check out the following workflows (Chimera removal, diversity metrics, longitudinal study) available at $HOME/Resources/scripts/ or on GitHub  https://www.github.com/Preve92/MicroEcologyWorkflows/ "
    echo
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
else
    exportDir=$outputDir/exported-features
    mkdir -p $exportDir
    echo
    echo "The features will be exported in $exportDir"

    time qiime tools export \
         --input-path $table \
         --output-path $exportDir

    time qiime tools export \
         --input-path $rootedTree \
         --output-path $exportDir

    time qiime tools export \
         --input-path $taxonomyDir/taxonomy.qza \
         --output-path $exportDir

    time qiime tools export \
         --input-path $repSeqs \
         --output-path $exportDir

    sed -i "1 s/^.*$/#OTUID\ttaxonomy\tconfidence/" $exportDir/taxonomy.tsv

    biom add-metadata \
         -i $exportDir/feature-table.biom \
         --observation-metadata-fp $exportDir/taxonomy.tsv \
         --observation-header OTUID,taxonomy,confidence \
         --sc-separated taxonomy \
         -o $exportDir/feature-table-taxonomy.biom

    echo
    echo "BIOM file with taxa table and taxonomy saved as: $exportDir/feature-table_taxonomy.biom"
    echo
    echo "Rooted tree saved as: $exportDir/tree.nwk"
    echo
    echo "Representative sequences saved as: $exportDir/dna-sequences.fasta"
    echo
    echo "All QIIME2 artifacts provenance and other metadata are saved in directories named after the artifacts' UUID."
fi

echo
echo "  ---  THIS SCRIPT ENDS HERE  ---  "
echo
