#!/bin/bash

function usage {
    echo "Usage: patch [OPTIONS] TABLE_NAME COLUMN_NAMES"
    echo
    echo "  Generate SQL-commands from patch file provided in stdin."
    echo
    echo "Options:"
    echo
    echo -e "  -d=C, --delimiter=C\t\tUse character C as column delimiter"
    echo -e "  -p=Col, --primary=Col\t\tComma-separated list of column numbers (1-based) which are primary keys"
    echo -e "  -h, --help\t\t\tShow this message and exit"
    exit
}

if [[ $# -lt 2 ]]; then
    usage
    exit
fi

# set defaults
PRIMARY_COLS=1

while [[ $# -gt 2 ]]; do
    key="$1"
    case $key in
        -d=*|--delimiter=*)
        DELIM="${key#*=}"
        shift
        ;;
        -p=*|--primary=*)
        PRIMARY_COLS="${key#*=}"
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

TABLE_NAME=$1
COLUMN_NAMES=$2
shift 2

DELIMITER=${DELIM:-','}

# get options as list
IFS=',' read -ra COLS <<< "$COLUMN_NAMES"
IFS=',' read -ra PRIMARYS <<< "$PRIMARY_COLS"

section=1
rownumber=1
in_buffer=()
block_rowa_number=1

# read in patch
while read line
do
    # mode header
    if [[ $line =~ ^[0-9]+(,[0-9]+)?[adc][0-9]+(,[0-9]+)?$ ]]; then
        if [[ $mode == "c" ]]; then
            # there could possibly be open deletions of the previous change
            while [[ $block_rowa_number -le ${#in_buffer[@]} ]]; do
                # create deletion
                where=" "
                where_no=1
                for pk_ix in "${PRIMARYS[@]}"; do
                    if [[ $where_no -gt 1 ]]; then
                        # add leading comma
                        where="$where AND "
                    fi

                    where="$where${COLS[$pk_ix-1]}=\"${rowa[$pk_ix-1]}\""
                    ((where_no++))
                done
                echo "DELETE FROM $TABLE_NAME WHERE$where LIMIT 1;"

                ((block_rowa_number++))
            done
        fi

        mode=${line//[^acd]/}  # either a=addition, c=change or d=deletion
        section=1
        rownumber=1
        block_rowa_number=1
        in_buffer=()

        continue
    fi

    # diff section
    if [[ $line == "---" ]]; then
        section=2
        block_rownumber=1
        continue
    fi

    # process line
    row=${line#[<>] }  # remove leading "> "
    IFS="$DELIMITER" read -ra rowb <<< "$row"

    # addition
    if [[ $mode == "a" && $section -eq 1 ]]; then
        values=${row//|/\",\"}
        values="(\"$values\")"
        echo "INSERT INTO $TABLE_NAME VALUES $values;"
    fi

    # deletion
    if [[ $mode == "d" && $section -eq 1 ]]; then
        where=" "
        where_no=1

        for pk_ix in "${PRIMARYS[@]}"; do
            if [[ $where_no -gt 1 ]]; then
                # add leading comma
                where="$where AND "
            fi

            where="$where${COLS[$pk_ix-1]}=\"${rowb[$pk_ix-1]}\""
            ((where_no++))
        done

        echo "DELETE FROM $TABLE_NAME WHERE$where LIMIT 1;"
    fi

    # change
    if [[ $mode == "c" ]]; then
        if [[ $section -eq 1 ]]; then
            # first section: removal
            # fill in buffer
            in_buffer+=($row)
        else
            IFS="$DELIMITER" read -ra rowa <<< ${in_buffer[$block_rowa_number-1]}

            # check for identical row identifiers
            same_rows=0
            until [[ $same_rows -eq 1 ]]; do
                same_rows=1
                for pk_ix in "${PRIMARYS[@]}"; do
                    if [[ ${rowa[$pk_ix-1]} != ${rowb[$pk_ix-1]} ]]; then
                        same_rows=0
                        break
                    fi
                done

                if [[ $same_rows -ne 1 ]]; then
                    if [[ $block_rowa_number -ge ${#in_buffer[@]} || ${rowa[$pk_ix-1]} > ${rowb[$pk_ix-1]} ]]; then
                        # real insertion first
                        values=${row//|/\",\"}
                        values="(\"$values\")"
                        echo "INSERT INTO $TABLE_NAME VALUES $values;"

                        # consume next line from stdin now
                        continue 2
                    else
                        # create deletion
                        where=" "
                        where_no=1
                        for pk_ix in "${PRIMARYS[@]}"; do
                            if [[ $where_no -gt 1 ]]; then
                                # add leading comma
                                where="$where AND "
                            fi

                            where="$where${COLS[$pk_ix-1]}=\"${rowa[$pk_ix-1]}\""
                            ((where_no++))
                        done
                        echo "DELETE FROM $TABLE_NAME WHERE$where LIMIT 1;"

                        ((block_rowa_number++))
                        IFS="$DELIMITER" read -ra rowa <<< ${in_buffer[$block_rowa_number-1]}
                    fi
                fi
            done
            # rows are the same based on its primary keys

            # calculate WHERE statement
            where=" "
            where_no=1
            for pk_ix in "${PRIMARYS[@]}"; do
                if [[ $where_no -gt 1 ]]; then
                    # add trailing AND
                    where="$where AND "
                fi

                where="$where${COLS[$pk_ix-1]}=\"${rowb[$pk_ix-1]}\""
                ((where_no++))
            done

            # calculate UPDATEs
            update=" "
            update_no=1
            col_no=0
            for col in "${COLS[@]}"; do
                ((col_no++))

                if [[ ${rowa[$col_no-1]} == ${rowb[$col_no-1]} ]]; then
                    # identical, so no update needed
                    continue
                fi

                if [[ $update_no -gt 1 ]]; then
                    # add trailing comma
                    update="$update, "
                fi

                update="$update${COLS[$col_no-1]}=\"${rowb[$col_no-1]}\""
                ((update_no++))
            done

            echo "UPDATE $TABLE_NAME SET$update WHERE$where LIMIT 1;"

            ((block_rowa_number++))
        fi
    fi

    ((rownumber++))
done < "${1:-/dev/stdin}"

if [[ $mode == "c" ]]; then
    # there could possibly be open deletions of the previous change
    while [[ $block_rowa_number -le ${#in_buffer[@]} ]]; do
        # create deletion
        where=" "
        where_no=1
        for pk_ix in "${PRIMARYS[@]}"; do
            if [[ $where_no -gt 1 ]]; then
                # add leading comma
                where="$where AND "
            fi

            where="$where${COLS[$pk_ix-1]}=\"${rowa[$pk_ix-1]}\""
            ((where_no++))
        done
        echo "DELETE FROM $TABLE_NAME WHERE$where LIMIT 1;"

        ((block_rowa_number++))
    done
fi
