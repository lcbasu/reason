#!/usr/bin/env bash
# Copyright (c) 2015-present, Facebook, Inc. All rights reserved.

set -eu

WARNING='\033[0;31m'
SUCCESS='\033[0;32m'
INFO=''
DEBUG=''
RESET='\033[0m'
VERBOSE=${VERBOSE:-}
OCAML_VERSION=`echo $(ocaml -version) | egrep -o '[0-9]+.[0-9]+.[0-9]+' | head -1`
OCAML_VERSION=${OCAML_VERSION:-"4.02.3"}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

REFMT="$DIR/../refmt_impl.native"

if [[ -f REFMT ]];
then
    echo "Cannot find refmt at $REFMT" 1>&2
    exit 1;
fi

UNIT_TEST_INPUT=$DIR/unit_tests/input

UNIT_TEST_OUTPUT=$DIR/unit_tests/actual_output

UNIT_TEST_EXPECTED_OUTPUT=$DIR/unit_tests/expected_output


TYPE_TEST_INPUT=$DIR/typeCheckedTests/input

TYPE_TEST_OUTPUT=$DIR/typeCheckedTests/actual_output

TYPE_TEST_EXPECTED_OUTPUT=$DIR/typeCheckedTests/expected_output


ERROR_TEST_INPUT=$DIR/errorTests/input

ERROR_TEST_OUTPUT=$DIR/errorTests/actual_output

ERROR_TEST_EXPECTED_OUTPUT=$DIR/errorTests/expected_output


PRINTER_TEST_INPUT=$DIR/printerTests/input

PRINTER_TEST_OUTPUT=$DIR/printerTests/actual_output

PRINTER_TEST_EXPECTED_OUTPUT=$DIR/printerTests/expected_output


FAILED_TESTS=$DIR/failed_tests

function info() {
    printf "${INFO}$1${RESET}\n"
}

function debug() {
    if [ ! -z "$VERBOSE" ]; then
        printf "${DEBUG}$1${RESET}\n"
    fi
}

function success() {
    printf "${SUCCESS}$1${RESET}\n"
}

function output() {
    printf "$1\n"
}

function warning() {
    printf "${WARNING}$1${RESET}\n"
}

function setup_test_dir() {
    echo "Setting up test dirs actual_output alongside the tests' expected_output"
    mkdir -p $UNIT_TEST_OUTPUT $TYPE_TEST_OUTPUT $ERROR_TEST_OUTPUT $PRINTER_TEST_OUTPUT
    touch $FAILED_TESTS
}

setup_test_dir

set +e

function stdin_test() {
    INPUT_FILE=$1
    OUTPUT_FILE=$2
    EXPECTED_OUTPUT_FILE=$3
    # explicitly pass in heuristics file because idempotent tests read from output directory
    HEURISTICS_FILE=$4

    FILENAME=$(basename $INPUT_FILE)
    FILEEXT="${FILENAME##*.}"

    if [[ $FILEEXT = "re" ]]; then
      cat $INPUT_FILE | $REFMT --interface false --print-width 50 --parse re --print re 2>&1 > $OUTPUT_FILE
    elif [[ $FILEEXT = "rei" ]]; then
      cat $INPUT_FILE | $REFMT --interface true --print-width 50 --parse re --print re 2>&1 > $OUTPUT_FILE
    elif [[ $FILEEXT = "ml" ]]; then
      cat $INPUT_FILE | $REFMT --heuristics-file $HEURISTICS_FILE --interface false --print-width 50 --parse ml --print re 2>&1 > $OUTPUT_FILE
    elif [[ $FILEEXT = "mli" ]]; then
      cat $INPUT_FILE | $REFMT --heuristics-file $HEURISTICS_FILE --interface true --print-width 50 --parse ml --print re 2>&1 > $OUTPUT_FILE
    else
      warning "  ⊘ FAILED --use-stdin \n"
      info "  Cannot determine default implementation parser for extension ${FILEEXT}"
      return 1
    fi

    if ! [[ $? -eq 0 ]]; then
        warning "  ⊘ FAILED --use-stdin \n"
        info "  There was an error when testing --use-stdin"
        info "  for input file $INPUT_FILE"
        info "  and output file $OUTPUT_FILE${RESET}"
        echo ""
        return 1
    fi

    debug "  Comparing --use-stdin results:  diff $OUTPUT_FILE $EXPECTED_OUTPUT_FILE"
    diff --unchanged-line-format="" --new-line-format=":%dn: %L" --old-line-format=":%dn: %L" $OUTPUT_FILE $EXPECTED_OUTPUT_FILE

    if ! [[ $? -eq 0 ]]; then
        warning "  ⊘ FAILED --use-stdin \n"
        info "  ${INFO}$OUTPUT_FILE${RESET}"
        info "  doesn't match expected output"
        info "  ${INFO}$EXPECTED_OUTPUT_FILE${RESET}"
        echo ""
        return 1
    fi
    return 0
}

function unit_test() {
    FILE=$1
    INPUT=$2
    OUTPUT=$3
    EXPECTED_OUTPUT=$4

    FILENAME=$(basename $FILE)
    FILEEXT="${FILENAME##*.}"


    info "Unit Test: $FILE"
    if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ] || [ "$(basename $FILE)" != "$(basename $FILE .mli)" ]; then
        if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ]; then
          REFILE="$(basename $FILE .ml).re"
        else
          REFILE="$(basename $FILE .mli).rei"
        fi
        debug "$REFMT --heuristics-file $INPUT/arity.txt --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$REFILE"
        $REFMT --heuristics-file $INPUT/arity.txt --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$REFILE
        if ! [[ $? -eq 0 ]]; then
            warning "  ⊘ TEST FAILED CONVERTING ML TO RE\n"
            return 1
        fi
        FILE=$REFILE
    else
      debug "  '$REFMT --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$FILE'"
      $REFMT --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$FILE
    fi

    OFILE="${FILE}"
    VERSION_SPECIFIC_FILE="${FILE}.${OCAML_VERSION}"
    if [ -f "${EXPECTED_OUTPUT}/${VERSION_SPECIFIC_FILE}" ]; then
        echo "Found test file specific to version ${OCAML_VERSION}..."
        OFILE="${VERSION_SPECIFIC_FILE}"
    fi

    debug "  Comparing results:  diff $OUTPUT/$FILE $EXPECTED_OUTPUT/$OFILE"

    diff --unchanged-line-format="" --new-line-format=":%dn: %L" --old-line-format=":%dn: %L" $OUTPUT/$FILE $EXPECTED_OUTPUT/$OFILE

    if ! [[ $? -eq 0 ]]; then
        warning "  ⊘ FAILED\n"
        info "  ${INFO}$OUTPUT/$FILE${RESET}"
        info "  doesn't match expected output"
        info "  ${INFO}$EXPECTED_OUTPUT/$OFILE${RESET}"
        echo ""
        return 1
    fi

    debug "Testing --use-stdin"
    stdin_test $INPUT/$1 $OUTPUT/$FILE $EXPECTED_OUTPUT/$OFILE $INPUT/arity.txt

    if ! [[ $? -eq 0 ]]; then
      return 1
    else
      success "  ☑ PASS"
      echo
    fi
}

function idempotent_test() {
    FILE=$1
    INPUT=$2
    OUTPUT=$3

    FILENAME=$(basename $FILE)
    FILEEXT="${FILENAME##*.}"

    info "Idempotent Test: $FILE"
    if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ] || [ "$(basename $FILE)" != "$(basename $FILE .mli)" ]; then
        if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ]; then
          REFILE="$(basename $FILE .ml).re"
        else
          REFILE="$(basename $FILE .mli).rei"
        fi
        debug "  Converting $FILE to $REFILE:"

        debug "  Formatting Once: $REFMT --heuristics-file $INPUT/arity.txt --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$REFILE"
        $REFMT --heuristics-file $INPUT/arity.txt --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$REFILE
        if ! [[ $? -eq 0 ]]; then
            warning "⊘ FAILED\n"
            return 1
        fi
        FILE=$REFILE
        debug "  Generating output again: $REFMT --print-width 50 --print re $OUTPUT/$FILE 2>&1 > $OUTPUT/$FILE.formatted"
        $REFMT --print-width 50 --print re $OUTPUT/$FILE 2>&1 > $OUTPUT/$FILE.formatted
    else
      debug "  Formatting Once: '$REFMT --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$FILE'"
      $REFMT --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$FILE

      debug "  Generating output again: $REFMT --print-width 50 --print re $OUTPUT/$FILE 2>&1 > $OUTPUT/$FILE.formatted"
      $REFMT --print-width 50 --print re $OUTPUT/$FILE 2>&1 > $OUTPUT/$FILE.formatted
    fi

    diff --unchanged-line-format="" --new-line-format=":%dn: %L" --old-line-format=":%dn: %L" $OUTPUT/$FILE $OUTPUT/$FILE.formatted
    if ! [[ $? -eq 0 ]]; then
        warning "⊘ FAILED\n"
        info "  ${INFO}$OUTPUT/$FILE.formatted${RESET}\n"
        info "  is not same as"
        info "  ${INFO}$OUTPUT/$FILE${RESET}"
        return 1
    fi

    debug "Testing --use-stdin"
    stdin_test $INPUT/$1 $OUTPUT/$FILE $OUTPUT/$FILE $INPUT/arity.txt

    if ! [[ $? -eq 0 ]]; then
      return 1
    else
      stdin_test $OUTPUT/$FILE $OUTPUT/$FILE.formatted $OUTPUT/$FILE $INPUT/arity.txt
      if ! [[ $? -eq 0 ]]; then
        return 1
      else
        success "  ☑ PASS"
        echo
      fi
    fi
}

function typecheck_test() {
    FILE=$1
    INPUT=$2
    OUTPUT=$3

    info "Typecheck Test: $FILE"
    if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ] || [ "$(basename $FILE)" != "$(basename $FILE .mli)" ]; then
        if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ]; then
          REFILE="$(basename $FILE .ml).re"
        else
          REFILE="$(basename $FILE .mli).rei"
        fi
        debug "  Converting $FILE to $REFILE:"
        debug "$REFMT --heuristics-file $INPUT/arity.txt --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$REFILE"
        $REFMT --heuristics-file $INPUT/arity.txt --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$REFILE
        if ! [[ $? -eq 0 ]]; then
            warning "  ⊘ FAILED\n"
            return 1
        fi
        FILE=$REFILE
    else
        debug "  Formatting: $REFMT --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$FILE"
        $REFMT --print-width 50 --print re $INPUT/$FILE 2>&1 > $OUTPUT/$FILE
        if ! [[ $? -eq 0 ]]; then
            warning "  ⊘ FAILED\n"
            return 1
        fi
    fi
    if [ "$(basename $FILE)" != "$(basename $FILE .re)" ]; then
      COMPILE_FLAGS="-intf-suffix .rei -impl"
    else
      COMPILE_FLAGS="-intf"
    fi

    debug "  Compiling: ocamlc -c -pp $REFMT $COMPILE_FLAGS $OUTPUT/$FILE"
    ocamlc -c -pp "$REFMT --print binary" $COMPILE_FLAGS "$OUTPUT/$FILE"
    if ! [[ $? -eq 0 ]]; then
        warning "  ⊘ FAILED\n"
        return 1
    fi

    success "  ☑ PASS"
    echo
}

function error_test() {
    FILE=$1
    INPUT=$2
    OUTPUT=$3
    EXPECTED_OUTPUT=$4

    info "Error Test: $FILE"
    if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ] || [ "$(basename $FILE)" != "$(basename $FILE .mli)" ]; then
      warning "  ⊘ FAILED: .ml files should not need to be run against error tests. \n"
      return 1
    else
      debug "  '$REFMT --print-width 50 --print re $INPUT/$FILE &> $OUTPUT/$FILE'"
      # ensure errors are not absolute filepaths
      cd $INPUT
      $REFMT --print-width 50 --print re $(basename $FILE) &> $OUTPUT/$FILE
      cd - > /dev/null
    fi

    debug "  Comparing results:  diff $OUTPUT/$FILE $EXPECTED_OUTPUT/$FILE"

    diff --unchanged-line-format="" --new-line-format=":%dn: %L" --old-line-format=":%dn: %L" $OUTPUT/$FILE $EXPECTED_OUTPUT/$FILE

    if ! [[ $? -eq 0 ]]; then
        warning "  ⊘ FAILED\n"
        info "  ${INFO}$OUTPUT/$FILE${RESET}"
        info "  doesn't match expected output"
        info "  ${INFO}$EXPECTED_OUTPUT/$FILE${RESET}"
        echo ""
        return 1
    fi

    success "  ☑ PASS"
    echo
}

function printer_test() {
    FILE=$1
    MLFILE="$(basename $FILE .re).ml"
    INPUT=$2
    OUTPUT=$3
    EXPECTED_OUTPUT=$4

    VERSION_SPECIFIC_MLFILE="${MLFILE}.${OCAML_VERSION}"
    if [ -f "${EXPECTED_OUTPUT}/${VERSION_SPECIFIC_MLFILE}" ]; then
        echo "Found test file specific to version ${OCAML_VERSION}..."
        MLFILE="${VERSION_SPECIFIC_MLFILE}"
    fi

    info "Printer Test: $FILE"
    if [ "$(basename $FILE)" != "$(basename $FILE .ml)" ] || [ "$(basename $FILE)" != "$(basename $FILE .mli)" ]; then
      warning "  ⊘ FAILED: .ml files should not need to be run against printer tests. \n"
      return 1
    else
      debug "  '$REFMT --parse re --print ml --add-printers --add-runtime $INPUT/$FILE &> $OUTPUT/$MLFILE'"
      # ensure errors are not absolute filepaths
      cd $INPUT
      $REFMT --parse re --print ml --add-printers --add-runtime $(basename $FILE) &> $OUTPUT/$MLFILE
      cd - > /dev/null
    fi

    debug "  Comparing results:  diff $OUTPUT/$MLFILE $EXPECTED_OUTPUT/$MLFILE"

    diff --unchanged-line-format="" --new-line-format=":%dn: %L" --old-line-format=":%dn: %L" $OUTPUT/$MLFILE $EXPECTED_OUTPUT/$MLFILE

    if ! [[ $? -eq 0 ]]; then
        warning "  ⊘ FAILED\n"
        info "  ${INFO}$OUTPUT/$MLFILE${RESET}"
        info "  doesn't match expected output"
        info "  ${INFO}$EXPECTED_OUTPUT/$MLFILE${RESET}"
        echo ""
        return 1
    fi

    success "  ☑ PASS"
    echo
}


cd $UNIT_TEST_INPUT && find . -type f \( -name "*.re*" -or -name "*.ml*" \) | while read file; do
        unit_test $file $UNIT_TEST_INPUT $UNIT_TEST_OUTPUT $UNIT_TEST_EXPECTED_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed unit_test" >> $FAILED_TESTS
        fi

        idempotent_test $file $UNIT_TEST_INPUT $UNIT_TEST_OUTPUT $UNIT_TEST_EXPECTED_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed idempotent_test" >> $FAILED_TESTS
        fi
done

cd $TYPE_TEST_INPUT && find . -type f \( -name "*.re*" -or -name "*.ml*" \) | sort | while read file; do
        typecheck_test $file $TYPE_TEST_INPUT $TYPE_TEST_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed typecheck_test" >> $FAILED_TESTS
        fi
        unit_test $file $TYPE_TEST_INPUT $TYPE_TEST_OUTPUT $TYPE_TEST_EXPECTED_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed unit_test" >> $FAILED_TESTS
        fi
        idempotent_test $file $TYPE_TEST_INPUT $TYPE_TEST_OUTPUT $TYPE_TEST_EXPECTED_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed idempotent_test" >> $FAILED_TESTS
        fi
done

cd $ERROR_TEST_INPUT && find . -type f \( -name "*.re*" -or -name "*.ml*" \) | while read file; do
        error_test $file $ERROR_TEST_INPUT $ERROR_TEST_OUTPUT $ERROR_TEST_EXPECTED_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed error_test" >> $FAILED_TESTS
        fi
done

cd $PRINTER_TEST_INPUT && find . -type f \( -name "*.re*" \) | while read file; do
        printer_test $file $PRINTER_TEST_INPUT $PRINTER_TEST_OUTPUT $PRINTER_TEST_EXPECTED_OUTPUT
        if ! [[ $? -eq 0 ]]; then
            echo "$file -- failed printer_test" >> $FAILED_TESTS
        fi
done

if [[ -s $FAILED_TESTS ]]; then
  warning "Failed tests:"
  cat $FAILED_TESTS
  exit 1
fi

exit 0
