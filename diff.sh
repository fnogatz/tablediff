#!/bin/bash

function usage {
    echo "Usage: diff [OPTIONS] OLD_CSV NEW_CSV"
    echo
    echo "  Compare two CSV dumps to get the changed rows as patch file."
    echo
    echo "Options:"
    echo
    echo -e "  -d=C, --delimiter=C\t\tUse character C as column delimiter"
    echo -e "  -s=N, --skip=N\t\tSkip the first N lines of the CSV file"
    echo -e "  -p=Col, --primary=Col\t\tComma-separated list of columns to use as sort-key"
    echo -e "  -o=PATH, --output=PATH\tUse PATH for splitted CSV files"
    echo -e "  --empty\t\t\tEmpty the 'old' and 'new' dirs first"
    echo -e "  --simple\t\t\tUse simple mode (sort only)"
    echo -e "  -h, --help\t\t\tShow this message and exit"
    exit
}

if [[ $# -lt 2 ]]; then
    usage
fi

SKEY=1

while [[ $# -gt 2 ]]; do
    key="$1"
    case $key in
        -d=*|--delimiter=*)
        DELIM="${key#*=}"
        shift
        ;;
        -s=*|--skip=*)
        SKIP="${key#*=}"
        shift
        ;;
        -p=*|--primary=*)
        SKEY="${key#*=}"
        shift
        ;;
        -o=*|--output=*)
        OUTP="${key#*=}"
        shift
        ;;
        --empty)
        EMPTY_DIR=true
        shift
        ;;
        --simple)
        SIMPLE_MODE=true
        shift
        ;;
        -h|--help)
        usage
        shift
        ;;
        *)
        usage
        shift
        ;;
    esac
done

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OUT_PATH=${OUTP:-$DIR}
OLD_PATH=$OUT_PATH"/old"
NEW_PATH=$OUT_PATH"/new"
SKIPS=${SKIP:-0}
SORT_KEYS=${SKEY:-4}
OLD_CSV=$1
NEW_CSV=$2
DELIMITER=${DELIM:-','}

if [[ $EMPTY_DIR ]]; then
    # create and empty the paths
    mkdir -p $OLD_PATH
    mkdir -p $NEW_PATH
    rm -rf $OLD_PATH/*
    rm -rf $NEW_PATH/*
fi

if [[ $SIMPLE_MODE ]]; then
    #
    # version to simply sort the whole files
    #
    
    sort --field-separator=$DELIMITER --key=$SORT_KEYS -o $OLD_PATH/"old.csv" $OLD_CSV &
    sort --field-separator=$DELIMITER --key=$SORT_KEYS -o $NEW_PATH/"new.csv" $NEW_CSV &
    wait
    
    diff $OLD_PATH/"old.csv" $NEW_PATH/"new.csv"
    exit
fi

#
# version using splitting
#

IFS=',' read -ra SKEYS <<< "$SORT_KEYS"
SKEYS_LENGTH=${#SKEYS[@]}
SORTS=${SKEYS[@]: -2}

if [[ $SKEYS_LENGTH -gt 2 ]]; then
    # split files first as they can not be sorted otherwise
    SPLITS=${SKEYS[@]:0:$(expr $SKEYS_LENGTH - 2)} # get all keys but the last two
    FILENAME_PATTERN=${SPLITS[*]}
    FILENAME_PATTERN=\$${FILENAME_PATTERN// /\"-\"\$}
    CMD_OLD="FNR > skips {print > out\"/\"$FILENAME_PATTERN\".csv\"}"
    CMD_NEW="FNR > skips {print > out\"/\"$FILENAME_PATTERN\".csv\"}"
    #echo $CMD_OLD && exit

    # run split in parallel (note "&" sign at the end)
    awk -v out="$OLD_PATH" -v skips="$SKIPS" -F "$DELIMITER" "$CMD_OLD" $OLD_CSV &
    awk -v out="$NEW_PATH" -v skips="$SKIPS" -F "$DELIMITER" "$CMD_NEW" $NEW_CSV &
    wait
else
    # simply copy files to their destination path
    cp $OLD_CSV $OLD_PATH"/file.csv" &
    cp $NEW_CSV $NEW_PATH"/file.csv" &
    wait

    if [[ $SKEYS_LENGTH -eq 1 ]]
    then
        SORTS=${SKEYS[@]: -1}
    fi
fi

# bitwise comparison to remove identical files
for f in "$OLD_PATH"/*; do cmp -s $f $NEW_PATH"/"${f##*/} && rm $f && rm $NEW_PATH"/"${f##*/}; done

# do simultaneously full sort
SORT_PATTERN=${SORTS[*]}
SORT_PATTERN=${SORT_PATTERN/ /,}
for f in "$OLD_PATH"/*; do
    [ -e "$f" ] || continue
    sort --field-separator=$DELIMITER --key="$SORT_PATTERN" -o $f $f &
    [ -e $NEW_PATH"/"${f##*/} ] || continue
    sort --field-separator=$DELIMITER --key="$SORT_PATTERN" -o $NEW_PATH"/"${f##*/} $NEW_PATH"/"${f##*/} &
done
wait

# bitwise comparison to remove identical sorted files
for f in "$OLD_PATH"/*; do
    [ -e "$f" ] || continue
    cmp -s $f $NEW_PATH"/"${f##*/} && rm $f && rm $NEW_PATH"/"${f##*/};
done

diff -arN "$OLD_PATH" "$NEW_PATH";
