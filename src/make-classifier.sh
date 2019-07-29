#!/bin/bash

# Title: 16S rRNA gene classifier training
# Author: Marco Prevedello
# Date: 2019-05-09

## Get script location
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

## Output essential information
echo "--- IMPORTANT USER INFORMATION ---"
echo
echo "This script will train a 16S rRNA gene classifier (e.g. Silva, GreenGenes, etc.) for qiime2 workflow. That is, it will output a trained classifier in .qza format."
echo
echo " The user is required to have access to the untrained classifier, which MUST be composed by the 16S sequences in FASTA format, and the reference taxonomy in TSV format. Additionally, the user shall know the exact location of the untrained classifier, and the pair of 16S amplification primer used."
echo
echo "This script allow the choice of common primers for amplification of the hypervariable regions V4 (515F/806R) and V3-V4 (314F/806R). However, if other primers have been used, the exact sequence must be typed by the user. Note that only the actual DNA-binding (i.e., biological) sequence contained within a primer construct must be inserted. And any non-biological, non-binding sequence, e.g., adapter, linker, or barcode sequences should be included. If you are not sure what section of your primer sequences are actual DNA-binding, you should consult whoever constructed your sequencing library, your sequencing center, or the original source literature on these primers. If your primer sequences are > 30 nt long, they most likely contain some non-biological sequence and will not be accepted by this script."
echo
echo "This script REQUIRE a loaded CONDA ENVIRONMENT with QIIME2-2019.4"
echo
read -p "Do you want to continue?[y/n] " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

## Obtain classifier location
echo
echo "Type full path of the classifier FASTA file. Default is \"~/resources/16S-classifiers/midas_s123_213/MiDAS_S123_2.1.3.fasta\""
echo
read -p "FASTA classifier path: " classifierFASTA
if [[ ! $classifierFASTA =~ (.fasta)$ ]]; then
    classifierFASTA="/home/marco/resources/16S-classifiers/midas_s123_213/MiDAS_S123_2.1.3.fasta"
fi
echo
echo "Type full path of the classifier taxonomy. Default is \"~/resources/16S-classifiers/midas_s123_213/MiDAS_S123_2.1.3.tax\""
echo
read -p "Taxonomy classifier path[.tax/.txt/.tsv] " classifierTaxonomy
if [[ ! $classifierTaxonomy =~ (.t[axs][xtv])$ ]]; then
    classifierTaxonomy="/home/marco/resources/16S-classifiers/midas_s123_213/MiDAS_S123_2.1.3.tax"
fi
classifierName=${classifierFASTA##*/}
classifierName=${classifierName%.fasta}

## Obtain primer sequence
x=0
while [[ x -eq 0 ]]; do
    echo
    echo "Type the primer used, either name or forward and reverse primer sequences separated by a forward slash (F/R). (Default 314F/806R)"
    read -p "Amplification primers:[515F/806R, 314F/806R, seq.] " primers
    if [[ -z $primers ]] || [[ $primers =~ (314[fF]/806[rR]) ]]; then
        primers="314F/806R"
        region="V3-V4"
        primerF="CCTACGGGNGGCWGCAG"
        primerR="GGACTACHVGGGTWTCTAAT"
        echo "Primers $primers for the region $region are selected"
        echo "The forward primer sequence is $primerF"
        echo "The reverse primer sequence is $primerR"
        read -p "Is this correct?[y/n] " -n 1 -r
        if [[ $REPLY =~ [yY] ]]; then
            x=1
        else
            x=0
        fi
    elif [[ $primers =~ (515[fF]/806[rR]) ]]; then
        primers="515F/806R"
        region="V4"
        primerF="GTGCCAGCMGCCGCGGTAA"
        primerR="GGACTACHVGGGTWTCTAAT"
        echo "Primers $primers for the region $region are selected"
        echo "The forward primer sequence is $primerF"
        echo "The reverse primer sequence is $primerR"
        read -p "Is this correct?[y/n] " -n 1 -r
        if [[ $REPLY =~ [yY] ]]; then
            x=1
        else
            x=0
        fi
    else
        primerR=${primers##*/}
        primerF=${primers%$primerR}
        primers="custom"
        region="custom"
        if [[ $primerF -gt 30 ]] || [[ $primerR -gt 30 ]]; then
            "The primers sequences given is too long"
            x=0
        else
            echo "Primers $primers for the region $region are selected"
            echo "The forward primer sequence is $primerF"
            echo "The reverse primer sequence is $primerR"
            read -p "Is this correct?[y/n] " -n 1 -r
            if [[ $REPLY =~ [yY] ]]; then
                x=1
            else
                x=0
            fi
        fi
    fi
done

## Obtain parameters for extracting training reads
echo
echo "You can provide custom trimming length for the extracted region on which the classifier will be trained."
echo
echo "N.B. This is advised only for analysis on TRIMMED SINGLE-END sequencing approaches!"
echo "And the trimming length must be equal or shorted than the trimmed single-end reads length!"
echo
echo "If no value is provided, the default (0) is used, and no extracted region will be truncated."
read -p "Trimming length: " truncLen
if [[ ! $trunLen =~ [1-9]+ ]]; then truncLen=0; fi

echo
echo "You should now provide the min and max acceptable length of the extracter region on which the classifier will be trained."
if [[ $region == "V3-V4" ]]; then
    echo "If no input is provided, the default values (min=100, max=600) will be used"
    read -p "Min length: " minLen
    read -p "MAX length: " maxLen
    if [[ ! $minLen =~ [1-9]+ ]]; then minLen=100; fi
    if [[ ! $maxLen =~ [1-9]+ ]]; then maxLen=600; fi
elif [[ $region == "V4" ]]; then
    echo "If no input is provided, the default values (min=100, max=400) will be used"
    read -p "Min length: " minLen
    read -p "MAX length: " maxLen
    if [[ ! $minLen =~ [1-9]+ ]]; then minLen=100; fi
    if [[ ! $maxLen =~ [1-9]+ ]]; then maxLen=400; fi
elif [[ $region == "custom" ]]; then
    echo "If no input is provided, the default values (min=30, max=0) will be used"
    read -p "Min length: " minLen
    echo
    read -p "MAX length: " maxLen
    if [[ ! $minLen =~ [1-9]+ ]]; then minLen=30; fi
    if [[ ! $maxLen =~ [1-9]+ ]]; then maxLen=0; fi
else
    echo "An error occurred. Check the script and the info provided"
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

## Obtain output directory
echo
echo "Type desired output directory (Default is \"~/resources/16S-classifiers/trained\")"
read -p "Output directory: " outputDir
if [[ -z $outputDir ]]; then
    outputDir="$HOME/resources/16S-classifiers/trained/$classifierName"
elif [[ $outputDir =~ ^~ ]]; then
    outputDir=$HOME/${outputDir#\~}
fi
outputDir=${outputDir/\/\//\/}
mkdir -p $outputDir

## Import the classifier into qiime
time qiime tools import \
     --type 'FeatureData[Sequence]' \
     --input-path $classifierFASTA \
     --output-path $outputDir/$classifierName.qza

time qiime tools import \
     --type 'FeatureData[Taxonomy]' \
     --input-format HeaderlessTSVTaxonomyFormat \
     --input-path $classifierTaxonomy \
     --output-path $outputDir/ref-taxonomy.qza

## Extract the reads corresponding to the hypervariable region used
time qiime feature-classifier extract-reads \
     --i-sequences $outputDir/$classifierName.qza \
     --p-f-primer $primerF \
     --p-r-primer $primerR \
     --p-trunc-len $truncLen \
     --p-min-length $minLen \
     --p-max-length $maxLen \
     --o-reads $outputDir/ref-seqs.qza \
     --verbose &> $outputDir/extraction.log

## Train the classifier
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads $outputDir/ref-seqs.qza \
  --i-reference-taxonomy $outputDir/ref-taxonomy.qza \
  --o-classifier $outputDir/$classifierName-trained.qza \
  --verbose &> $outputDir/training.log

echo
echo "The trained classifier is saved as $outputDir/$classifierName-trained.qza"
echo
echo "Before use, the classifier should be tested on a set of demuiltiplexed and denoised representative sequences obtained with the choosen primers."
echo
read -p "Do you want to do it now?[y/n] " -n 1 -r
echo
if [[ $REPLY =~ [yY] ]]; then
    x=0
    while [[ x -eq 0 ]]; do
        read -p "Input the absolute path of the rep. reads for the test:[*.qza] " repSeqs
        if [[ ! $repSeqs =~ (.qza)$ ]]; then
            x=0
            echo "The path is incorrect"
        elif [[ $repSeqs =~ /$ ]]; then
            x=1
            repSeqs=${repSeqs%\/}
        elif [[ $repSeqs =~ ^~ ]]; then
            x=1
            repSeqs=$HOME/${repSeqs#\~}
        fi
        repSeqs=${repSeqs/\/\//\/}
        echo "$repSeqs will be used"
        read -p "Is this correct?[y/n] " -n 1 -r
        if [[ ! $REPLY =~ [yY] ]]; then
            x=0
            echo "You can retry"
        fi
    done
    ## Test the classifier using the representative sequences
    time qiime feature-classifier classify-sklearn \
         --i-classifier $outputDir/$classifierName-classifier.qza \
         --i-reads $repSeqs \
         --o-classification $outputDir/test-taxonomy.qza \
         --verbose &> $outputDir/test.log

    time qiime metadata tabulate \
         --m-input-file $outputDir/test-taxonomy.qza \
         --o-visualization $outputDir/test-taxonomy.qzv

    echo "The output of the test is saved as $outputDir/test-taxonomy.qzv and can be visualized."
else
    echo "Remember to do this before using the classifier!"
    echo "Check https://docs.qiime2.org/2019.4/tutorials/feature-classifier/ for further info."
fi

# The script ends here
